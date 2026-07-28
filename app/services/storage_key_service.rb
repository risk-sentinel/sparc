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
#   <prefix>/org/<org>/boundary/<boundary>/evidence/<uuid>/<token>
#   <prefix>/org/<org>/boundary/<boundary>/evidence/<uuid>/versions/<id>/<token>
#   <prefix>/org/<org>/boundary/<boundary>/documents/<kind>/<record>/<token>
#   <prefix>/org/<org>/boundary/<boundary>/scans/<id>/<token>
#   <prefix>/instance/users/<id>/avatar/<token>
#   <prefix>/instance/unscoped/<kind>/<record>/<token>
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
      when ScanRun           then boundary_segments(record.authorization_boundary) + [ "scans", id_of(record) ]
      when User              then [ "instance", "users", id_of(record), slug(name) ]
      else                        document_segments(record, name)
      end
    end

    # `try(:organization)` because Evidence reaches an organization only THROUGH
    # its boundary — it has no direct association. Asking for one it does not
    # have would raise, and a storage-layout detail must never be the reason an
    # upload fails.
    def evidence_segments(evidence)
      boundary_segments(evidence.authorization_boundary, evidence.try(:organization)) +
        [ "evidence", record_key(evidence) ]
    end

    # Nested UNDER the evidence it versions, so "everything for this artifact"
    # is one prefix and a per-version Object Lock rule can still target a single
    # immutable copy. That matters specifically in copy-per-version mode, where
    # each version owns independent bytes rather than referencing the shared
    # blob (see ArtifactVersionable#attach_version_content).
    def version_segments(version)
      evidence = version.evidence
      return [ "instance", "unscoped", "artifact_version", id_of(version) ] if evidence.nil?

      evidence_segments(evidence) + [ "versions", id_of(version) ]
    end

    def document_segments(record, name)
      kind = DOCUMENT_KINDS[record.class.name]
      return [ "instance", "unscoped", slug(record.class.name), id_of(record), slug(name) ] if kind.nil?

      boundary_segments(record.try(:authorization_boundary), record.try(:organization)) +
        [ "documents", kind, record_key(record) ]
    end

    # The tenancy path, in three tiers. An artifact with no tenant is NOT
    # dropped at the root; every object has an owner visible from the bucket
    # side.
    #
    #   org/<org>/boundary/<boundary>/…  one boundary owns it
    #   org/<org>/shared/…               the ORGANIZATION owns it, no single boundary does
    #   instance/unscoped/…              neither
    #
    # The `shared` tier is not a fallback, it is a real category. A
    # CdefDocument links to MANY boundaries through a join table and belongs to
    # an organization; a ProfileDocument is a shared baseline like a control
    # catalog. A component definition reused by three boundaries cannot live
    # under any one of their prefixes without lying about ownership — and an
    # org-scoped IAM policy should still cover it, which `org/<org>/shared/`
    # gives for free while a boundary-scoped policy correctly does not match.
    def boundary_segments(boundary, organization = nil)
      org = organization || boundary&.organization
      return [ "instance", "unscoped" ] if boundary.nil? && org.nil?

      org_segment = [ "org", slug(org&.slug || org&.name) || UNKNOWN ]
      return org_segment + [ "shared" ] if boundary.nil?

      org_segment + [ "boundary", slug(boundary.slug || boundary.name) || UNKNOWN ]
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
