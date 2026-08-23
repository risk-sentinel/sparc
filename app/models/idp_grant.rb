# frozen_string_literal: true

# #860 — one entitlement, as an IdP states it.
#
# A grant is a string in a claim. It says WHO holds WHICH role in WHAT scope,
# and nothing else: SPARC never learns what a role may do from a claim, and the
# IdP never learns it either. Permissions stay in-app; membership comes from the
# directory.
#
#   sparc:instance:{role}
#   sparc:org:{org_slug}:{role}
#   sparc:boundary:{org_slug}:{boundary_slug}:{role}
#
# The instance form is parsed unconditionally but only RESOLVES when the
# operator has named that role in SPARC_OIDC_INSTANCE_ROLES. Parsing it always
# is deliberate: an instance grant arriving at an instance that has not opted in
# should be reported to an administrator, not silently discarded as noise.
#
# ── Why the org segment is in the boundary form ───────────────────────────
#
# It is not needed to resolve anything: `authorization_boundaries.slug` carries
# a UNIQUE index that is not scoped to `organization_id`, so a boundary slug
# identifies a boundary on its own. It is carried anyway so that a grant naming
# an organization that does not own the named boundary can be REFUSED BY NAME
# rather than applied to the right boundary in the wrong tenant. That check
# costs one comparison and turns a mis-scoped directory group from a silent
# cross-tenant grant into a visible, named refusal.
#
# It also makes the string legible to the person creating the group in the IdP
# console, who is reading `sparc:boundary:acme:acme-prod:reviewer` and not a
# bare slug.
#
# ── Canonicalisation ──────────────────────────────────────────────────────
#
# Claim values are authored by hand in an IdP console and will differ in case
# and whitespace from the slugs they name. The #852 rule applies: decide the
# canonical form ONCE, compare canonically, and never let two representations
# drift. Slugs are generated lowercase, so canonical here is stripped and
# downcased — and it happens in this one place, not at each call site.
#
# ── This class does not touch the database ────────────────────────────────
#
# Parsing answers "is this a well-formed grant?" Resolution answers "does what
# it names exist?" They are separate because a well-formed grant naming an
# unknown boundary is a REPORTABLE state (it goes to the unmatched queue for an
# administrator to see), while a malformed string is usually just an unrelated
# directory group that happened to match the prefix.
class IdpGrant
  SCOPE_TYPES = %w[instance org boundary].freeze

  # Segment counts AFTER the configured prefix is removed.
  SEGMENTS = { "instance" => 2, "org" => 3, "boundary" => 4 }.freeze

  attr_reader :raw, :scope_type, :organization_slug, :boundary_slug, :role_name, :error

  def initialize(raw:, scope_type: nil, organization_slug: nil, boundary_slug: nil,
                 role_name: nil, error: nil)
    @raw = raw
    @scope_type = scope_type
    @organization_slug = organization_slug
    @boundary_slug = boundary_slug
    @role_name = role_name
    @error = error
  end

  def valid? = error.nil?
  def instance_scoped? = scope_type == "instance"
  def org_scoped? = scope_type == "org"
  def boundary_scoped? = scope_type == "boundary"

  # Parse every claim value that carries the configured prefix.
  #
  # Values without the prefix are DROPPED SILENTLY and deliberately: on a real
  # directory the claim carries every group the person belongs to, and reporting
  # each one as unmatched would bury the grants that genuinely failed to resolve
  # under hundreds of lines of noise. A value that carries the prefix and is
  # still malformed IS returned, because someone meant it for SPARC.
  def self.parse_all(values)
    Array(values).filter_map { |value| parse(value) }
  end

  # Returns an IdpGrant (valid or with an `error`), or nil when the value is not
  # addressed to SPARC at all.
  def self.parse(value)
    raw = value.to_s.strip
    return nil if raw.empty?

    prefix = canonicalize(SparcConfig.oidc_grants_prefix)
    canonical = canonicalize(raw)
    return nil unless prefix.present? && canonical.start_with?(prefix)

    segments = canonical.delete_prefix(prefix).split(":")
    scope_type = segments.first

    unless SCOPE_TYPES.include?(scope_type)
      return invalid(raw, "unknown scope type #{scope_type.inspect}; expected one of #{SCOPE_TYPES.join(', ')}")
    end

    expected = SEGMENTS.fetch(scope_type)
    if segments.length != expected
      return invalid(raw, "expected #{expected} segments after #{prefix.inspect}, got #{segments.length}")
    end

    return invalid(raw, "one or more segments are empty") if segments.any?(&:blank?)

    case scope_type
    when "instance"
      _, role_name = segments
      new(raw: raw, scope_type: "instance", role_name: role_name)
    when "org"
      _, organization_slug, role_name = segments
      new(raw: raw, scope_type: "org", organization_slug: organization_slug, role_name: role_name)
    else
      _, organization_slug, boundary_slug, role_name = segments
      new(raw: raw, scope_type: "boundary", organization_slug: organization_slug,
          boundary_slug: boundary_slug, role_name: role_name)
    end
  end

  # Stripped and downcased — see the note on canonicalisation above.
  def self.canonicalize(value) = value.to_s.strip.downcase

  def self.invalid(raw, reason) = new(raw: raw, error: reason)
  private_class_method :invalid

  def to_s = raw

  def ==(other)
    other.is_a?(IdpGrant) && other.scope_type == scope_type &&
      other.organization_slug == organization_slug &&
      other.boundary_slug == boundary_slug && other.role_name == role_name
  end
  alias eql? ==

  def hash = [ scope_type, organization_slug, boundary_slug, role_name ].hash
end
