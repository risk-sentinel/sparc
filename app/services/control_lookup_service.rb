# Cross-catalog control lookup (#902 follow-up).
#
# One implementation behind two front doors: the token-authenticated
# `Api::V1::ControlLookupsController` and the session-authenticated
# `ControlLookupsController` that the evidence control picker calls. The API is
# not reachable from the browser (Bearer only, no cookies), so without a shared
# service the picker would need a second, drifting copy of this logic — and a
# picker that disagrees with the validator about what exists is worse than no
# picker at all.
#
# The problem it solves: control identifiers have three legitimate forms (#852).
# SPARC *displays* the padded form (AC-02) and catalogs *store* the canonical
# one (ac-2), so a free-text field let users save links that matched nothing.
# Every search here runs against the canonical form as well as the raw string,
# so looking up what you see on screen finds what is actually stored.
class ControlLookupService
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100
  # Rows fetched per requested row, to refill the page after identical
  # identifiers from different catalogs collapse. 3 covers the catalogs
  # SPARC ships with (NIST Rev 4, Rev 5, FedRAMP KSI).
  OVERFETCH = 3

  Result = Struct.new(:controls, :total, :limit, :profile, keyword_init: true) do
    def scoped_to_profile? = profile.present?
  end

  def initialize(q: nil, family: nil, limit: nil, authorization_boundary_id: nil)
    @q = q.presence
    @family = family.presence
    @limit = limit
    @authorization_boundary_id = authorization_boundary_id.presence
  end

  def call
    scope = filtered_scope
    Result.new(
      controls: distinct_by_identifier(scope),
      total: scope.count,
      limit: resolved_limit,
      profile: scoped_profile
    )
  end

  # Does this identifier name a real control, in any form? Returns the
  # CatalogControl or nil.
  #
  # Scoped to this service on purpose. Making catalog resolution a shared
  # authority that profiles, converters and mappings all validate against is a
  # real and larger design question — catalogs are the source of truth, so
  # anything entering mid-stream has to relate back to one, and Rev 4 / Rev 5
  # translation (ControlIdNormalizer) bears on what "exists" even means. That
  # work is #911. This service only needs to answer the question for its own
  # read-only lookup, so it answers it here rather than pre-empting that design.
  def self.resolve(raw)
    canonical = ControlId.canonical(raw)
    return nil if canonical.blank? || canonical == "unknown"

    CatalogControl.where(control_id: canonical)
                  .or(CatalogControl.where(canonical_id: canonical))
                  .includes(:control_family).first
  end

  def self.serialize(control)
    {
      # What gets stored and written into OSCAL.
      control_id: control.canonical_identifier,
      # What a human recognises: AC-2(1).
      display_id: control.display_id,
      # SPARC's padded display/sort convention.
      padded_id: ControlId.padded(control.canonical_identifier),
      title: control.title,
      family_code: control.control_family&.code,
      family_name: control.control_family&.name,
      catalog_id: control.control_family&.control_catalog_id,
      # An enhancement is a control in its own right; the caller should not have
      # to re-parse the identifier to discover that.
      enhancement: control.canonical_identifier.include?(".")
    }
  end

  private

  attr_reader :q, :family, :authorization_boundary_id

  # The same control usually exists in several loaded catalogs — `ac-2` is in
  # both the Rev 4 and Rev 5 NIST catalogs. Returning both produces two rows a
  # user cannot tell apart, and picking either stores the identical identifier,
  # so the choice is not a choice.
  #
  # What this picker emits is an *identifier*, so it lists each identifier once.
  # Which catalog a reference belongs to is a real question — it is the heart of
  # #911 — but it is not one to ask someone through two indistinguishable rows.
  #
  # Over-fetches to fill the page after deduplication, bounded so a broad search
  # cannot pull the whole catalog into memory.
  def distinct_by_identifier(scope)
    scope.limit(resolved_limit * OVERFETCH)
         .to_a
         .uniq(&:canonical_identifier)
         .first(resolved_limit)
  end

  def filtered_scope
    scope = base_scope

    if q
      term      = "%#{CatalogControl.sanitize_sql_like(q.to_s.strip)}%"
      canonical = "%#{CatalogControl.sanitize_sql_like(ControlId.canonical(q))}%"
      scope = scope.where(
        "catalog_controls.control_id ILIKE :t OR catalog_controls.title ILIKE :t " \
        "OR catalog_controls.canonical_id ILIKE :c OR catalog_controls.label ILIKE :t",
        t: term, c: canonical
      )
    end

    scope = scope.where(control_families: { code: family.to_s.upcase }) if family
    scope
  end

  # Catalog content is global reference data, not boundary-scoped. But when a
  # boundary carries a baseline (#395, one profile per system) those are the
  # controls actually in scope for that system, so they are what a picker should
  # offer. Falls back to every catalog when no baseline is set — which is the
  # common case today, not an edge one, so the fallback is the load-bearing path.
  def base_scope
    scope = CatalogControl.includes(:control_family)
    return scope unless scoped_profile

    ids = scoped_profile.profile_controls.pluck(:control_id).map { |c| ControlId.canonical(c) }
    return scope if ids.empty?

    scope.where(control_id: ids).or(CatalogControl.includes(:control_family).where(canonical_id: ids))
  end

  def scoped_profile
    return @scoped_profile if defined?(@scoped_profile)

    @scoped_profile =
      authorization_boundary_id &&
      AuthorizationBoundary.find_by(id: authorization_boundary_id)&.profile_document
  end

  def resolved_limit
    (@limit.presence&.to_i || DEFAULT_LIMIT).clamp(1, MAX_LIMIT)
  end
end
