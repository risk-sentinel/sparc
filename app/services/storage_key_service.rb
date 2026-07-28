# frozen_string_literal: true

# #830 — derive a structured, deterministic object key for every blob SPARC
# stores, replacing ActiveStorage's flat namespace of random 28-character keys.
#
# Before this, a user avatar, an SSP upload, a scan result and a WORM-retained
# evidence artifact were indistinguishable by key and belonged to no visible
# tenant. That has consequences beyond tidiness:
#
#   * No prefix-scoped IAM. Least-privilege S3 policies are written against key
#     prefixes, so any principal that could read the bucket could read every
#     tenant's artifacts. sparc-iac already scopes its evidence roles to
#     `{boundary}/*/{repo}/{source}/`; SPARC's own storage could not participate.
#   * No lifecycle or retention per scope. S3 lifecycle rules and Object Lock
#     are prefix-driven, so evidence under a retention obligation could not be
#     separated from a user avatar.
#   * Unbounded offboarding. Deleting or exporting everything belonging to one
#     organization meant walking the database, with no way to verify
#     completeness from the bucket side.
#
# ── The scheme ────────────────────────────────────────────────────────────
#
#   <prefix>/sparc/users/<id>/avatar/<token>
#   <prefix>/sparc/unattributed/<kind>/<record>/<name>/<token>
#   <prefix>/<organization>/shared/<kind>/<record>/<token>
#   <prefix>/<organization>/<boundary>/evidence/<uuid>/<token>
#   <prefix>/<organization>/<boundary>/evidence/<uuid>/versions/<id>/<token>
#   <prefix>/<organization>/<boundary>/documents/<kind>/<record>/<token>
#   <prefix>/<organization>/<boundary>/scans/<id>/<token>
#
# The bucket root IS the tenant list: `sparc/` plus one folder per
# organization, and inside an organization, one folder per boundary. Someone
# browsing the bucket can see where to look without being told the convention,
# and a prefix-filtered LIST narrows to a tenant or a boundary in one hop.
#
# Constant segments are deliberately absent. An earlier draft wrote
# `organization/<org>/boundary/<boundary>/…`, which spends two path segments
# restating what the position already says and makes every LIST prefix longer
# for no gain.
#
# Ordered widest-scope-first so a single `s3:prefix` condition can express
# "this organization" or "this boundary" — the narrower the policy needs to be,
# the longer the prefix, which is the property prefix-scoped IAM depends on.
#
# ── Why the random token stays ────────────────────────────────────────────
#
# The final segment is still ActiveStorage's generated token. The key is
# derived and reproducible from the owning record *as a path*, but the leaf
# remains unguessable: some deployments serve blobs via a proxy that trusts the
# key, and a fully deterministic key would let anyone who knows a boundary slug
# and an evidence UUID construct the object path. Structure buys IAM scoping;
# the token keeps that from costing confidentiality.
#
# ── Boundary-less artifacts have an explicit home ─────────────────────────
#
# Avatars belong to a person, not a boundary, and several document types carry
# an optional boundary that may genuinely be unset. Rather than letting those
# fall back to the bucket root — the thing this issue exists to stop — they get
# a stated `instance/` location.
#
# NIST 800-53: AC-3 (Access Enforcement), AC-4 (Information Flow Enforcement),
# SC-4 (Information in Shared Resources), SI-12 (Information Management and
# Retention).
class StorageKeyService
  # Documents keyed by their own kind so a lifecycle rule can target, say,
  # every SSP upload without also matching evidence.
  DOCUMENT_KINDS = {
    "SspDocument" => "ssp", "SarDocument" => "sar", "SapDocument" => "sap",
    "PoamDocument" => "poam", "CdefDocument" => "cdef", "ProfileDocument" => "profile"
  }.freeze

  UNKNOWN = "unknown"

  # `sparc/` is the instance-wide namespace and therefore sits in the same
  # position as an organization folder. An organization whose name slugifies to
  # a reserved word would collide with it and its artifacts would land among
  # instance-level ones, so reserved names are disambiguated by id instead.
  RESERVED_TOP_LEVEL = %w[sparc].freeze

  INSTANCE = "sparc"

  class << self
    # The key for a blob about to be attached to `record` as `name`.
    # `token` is ActiveStorage's generated key, kept as the leaf.
    def key_for(record:, name:, token:)
      segments = [ prefix, *scope_segments(record, name), token ].compact
      segments.reject(&:blank?).join("/")
    end

    # Optional deployment prefix, for a bucket shared between instances
    # (staging and production, or two tenants of one operator). Unset in the
    # common case, where the bucket already belongs to one instance.
    def prefix
      slug(ENV.fetch("SPARC_STORAGE_PREFIX", nil)).presence
    end

    private

    def scope_segments(record, name)
      case record
      when Evidence          then evidence_segments(record)
      when ArtifactVersion   then version_segments(record)
      when ScanRun           then scan_segments(record)
      when User              then [ INSTANCE, "users", id_of(record), slug(name) ]
      else                        document_segments(record, name)
      end
    end

    # `try(:organization)` because Evidence reaches an organization only THROUGH
    # its boundary — it has no direct association. Asking for one it does not
    # have would raise, and a storage-layout detail must never be the reason an
    # upload fails.
    def evidence_segments(evidence)
      tenancy = boundary_segments(evidence.authorization_boundary, evidence.try(:organization))
      return unattributed_segments(evidence, :file) if tenancy.nil?

      tenancy + [ "evidence", record_key(evidence) ]
    end

    def scan_segments(scan_run)
      tenancy = boundary_segments(scan_run.authorization_boundary)
      return unattributed_segments(scan_run, :file) if tenancy.nil?

      tenancy + [ "scans", id_of(scan_run) ]
    end

    # Nested UNDER the evidence it versions, so "everything for this artifact"
    # is one prefix and a per-version Object Lock rule can still target a single
    # immutable copy. That matters specifically in copy-per-version mode, where
    # each version owns independent bytes rather than referencing the shared
    # blob (see ArtifactVersionable#attach_version_content).
    def version_segments(version)
      evidence = version.evidence
      return unattributed_segments(version, :content) if evidence.nil?

      evidence_segments(evidence) + [ "versions", id_of(version) ]
    end

    def document_segments(record, name)
      kind = DOCUMENT_KINDS[record.class.name]
      return unattributed_segments(record, name) if kind.nil?

      tenancy = boundary_segments(record.try(:authorization_boundary), record.try(:organization))
      return unattributed_segments(record, name) if tenancy.nil?

      tenancy + [ "documents", kind, record_key(record) ]
    end

    # Artifacts whose owner cannot be determined — no boundary AND no
    # organization. Kept in a NAMED quarantine rather than mixed in with
    # genuinely instance-wide files, because the two have opposite grant
    # stories: `sparc/users/` is safe to read broadly, while an unattributed
    # blob may well be tenant data whose association was lost. Anything landing
    # here is a data-quality signal, not a scope.
    def unattributed_segments(record, name)
      [ INSTANCE, "unattributed", slug(record.class.name) || UNKNOWN, id_of(record), slug(name) ]
    end

    # The tenancy path, in three tiers. An artifact with no tenant is NOT
    # dropped at the root; every object has an owner visible from the bucket
    # side.
    #
    #   <organization>/<boundary>/…   one boundary owns it
    #   <organization>/shared/…       the ORGANIZATION owns it, no single boundary does
    #   sparc/unattributed/…          neither
    #
    # The `shared` tier is not a fallback, it is a real category. A
    # CdefDocument links to MANY boundaries through a join table and belongs to
    # an organization; a ProfileDocument is a shared baseline like a control
    # catalog. A component definition reused by three boundaries cannot live
    # under any one of their prefixes without lying about ownership — and an
    # org-scoped IAM policy should still cover it, which `<organization>/shared/`
    # gives for free while a boundary-scoped policy correctly does not match.
    #
    # `shared` is likewise reserved: a boundary named "Shared" would otherwise
    # occupy the same position as the org-wide tier.
    def boundary_segments(boundary, organization = nil)
      org = organization || boundary&.organization
      return nil if boundary.nil? && org.nil?

      org_segment = [ organization_segment(org) ]
      return org_segment + [ "shared" ] if boundary.nil?

      org_segment + [ boundary_segment(boundary) ]
    end

    # An organization folder sits at the bucket root, in the same position as
    # `sparc/`, so a name that slugifies to a reserved word is disambiguated by
    # id rather than allowed to collide with the instance namespace.
    def organization_segment(org)
      name = slug(org&.slug || org&.name) || UNKNOWN
      return name unless RESERVED_TOP_LEVEL.include?(name)

      "#{name}-#{org.id}"
    end

    def boundary_segment(boundary)
      name = slug(boundary.slug || boundary.name) || UNKNOWN
      name == "shared" ? "#{name}-#{boundary.id}" : name
    end

    # Prefer a UUID, then a slug, then the id — whichever the record actually
    # carries. Reproducible from the record either way, which is the acceptance
    # criterion; a renamed record keeps its original key because ActiveStorage
    # keys are persisted and relocation is copy-then-update, never a rename.
    def record_key(record)
      slug(record.try(:uuid)) || slug(record.try(:slug)) || id_of(record)
    end

    def id_of(record) = record.id.to_s.presence || UNKNOWN

    # S3 tolerates far more than this, but keys end up in IAM policy documents,
    # lifecycle rules and CLI arguments, so the safe set is deliberately narrow.
    def slug(value)
      return nil if value.blank?

      value.to_s.strip.downcase
           .gsub(%r{[^a-z0-9._-]+}, "-")   # anything else, including "/", becomes a hyphen
           .gsub(/\.{2,}/, ".")            # ".." cannot survive — see below
           .gsub(/-{2,}/, "-")
           .gsub(/\A[.\-]+|[.\-]+\z/, "")  # no leading/trailing dot or hyphen
           .presence
    end
  end
end
