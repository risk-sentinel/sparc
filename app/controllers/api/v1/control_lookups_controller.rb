# Cross-catalog control lookup (#902 follow-up).
#
# Every other control route is catalog-scoped
# (`/api/v1/control_catalogs/:id/controls`), which is right for browsing a
# catalog but cannot answer "does this identifier name a real control, and what
# are my options?" for a caller that belongs to no catalog — which is exactly
# the question when linking evidence to controls.
#
# Free-text control ids were the defect this closes: SPARC displays the padded
# form (AC-02) while catalogs store the canonical one (ac-2), so a user typing
# what they saw produced a link that matched nothing, silently. Every seeded
# evidence link was dead this way.
#
# Shares ControlLookupService with the session-authenticated web endpoint that
# backs the picker, so the thing that offers identifiers and the thing that
# validates them cannot disagree.
#
# Endpoints:
#   GET /api/v1/controls?q=ac-2                    — search all loaded catalogs
#   GET /api/v1/controls?authorization_boundary_id=5 — prefer that baseline
#   GET /api/v1/controls/resolve?id=AC-02          — resolve one identifier
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Bearer token required)
#   AC-3 Access Enforcement (read-only; catalog content is global reference data)
#   CA-2 / CA-5 Consistent control identification across artifacts (#852)
#   SI-10 Information Input Validation (a caller cannot invent an identifier)
class Api::V1::ControlLookupsController < Api::V1::BaseController
  # GET /api/v1/controls
  def index
    result = lookup.call

    render json: {
      data: result.controls.map { |c| ControlLookupService.serialize(c) },
      meta: {
        total: result.total,
        limit: result.limit,
        # #1022 — `page`/`pages` so reaching rows 26+ does not require a
        # different paging model from every other index. `total`/`limit` stay:
        # they are the published contract (docs/api/endpoints/control-lookup.md)
        # and callers are written against them.
        page: result.page,
        pages: result.pages,
        # Lets a client say "showing this system's baseline" rather than
        # implying it searched everything.
        scoped_to_profile: result.scoped_to_profile?,
        profile_title: result.profile&.name
      }
    }
  end

  # GET /api/v1/controls/resolve
  #
  # The one question a validating client needs answered: does this identifier
  # name a real control, and what is its canonical form? Accepts any of the
  # three legitimate forms (AC-02, ac-2, "AC-2 (1)").
  def resolve
    raw = params[:id].to_s
    control = ControlLookupService.resolve(raw)

    if control
      render json: {
        data: ControlLookupService.serialize(control).merge(resolved: true, submitted: raw)
      }
    else
      render json: {
        error: "Unknown control identifier",
        details: [ "#{ControlId.padded(raw)} does not match any control in a loaded catalog" ],
        data: { resolved: false, submitted: raw, canonical: ControlId.canonical(raw) }
      }, status: :not_found
    end
  end

  private

  def lookup
    ControlLookupService.new(
      q: params[:q],
      family: params[:family],
      limit: page_size,
      page: params[:page],
      authorization_boundary_id: params[:authorization_boundary_id]
    )
  end

  # #1022 — honour the API-wide pagination convention as well as this endpoint's
  # own `?limit`.
  #
  # This is the largest collection in the API (4,054 controls) and it ignored
  # `?items` / `?per_page`, which every other index accepts. A caller using the
  # convention got 25 rows and NO indication their limit was dropped — the
  # envelope still reported `limit: 25`, so the response looked like a correct
  # answer to a different question.
  #
  # `limit` wins when both are given: it is the published contract for this
  # endpoint (docs/api/endpoints/control-lookup.md) and callers are written
  # against it. `items` before `per_page` matches
  # `BaseController#resolve_pagination_size`, so the precedence is the same one
  # every other endpoint uses.
  #
  # No cap needed here: ControlLookupService#resolved_limit already clamps to
  # 1..MAX_LIMIT, so `?items=999999` cannot reach the query.
  def page_size
    params[:limit].presence || params[:items].presence || params[:per_page].presence
  end
end
