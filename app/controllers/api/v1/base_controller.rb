# Base controller for all API v1 endpoints.
#
# Inherits from ActionController::API (not ApplicationController) to
# avoid CSRF, session, cookies, and other browser-specific middleware.
# Provides Bearer token authentication, RBAC authorization,
# JSON error handling, and pagination helpers.
#
class Api::V1::BaseController < ActionController::API
  include ApiAuthentication
  include Authorization
  include Pagy::Method

  before_action :authenticate_api_token!

  # Raised by `permit_strictly` when a request body carries fields the endpoint
  # does not accept. Carries the offending names and what was expected, so the
  # caller can correct the payload rather than guess which of the two failures
  # they hit.
  class UnrecognizedFields < StandardError
    attr_reader :fields, :permitted

    def initialize(fields, permitted)
      @fields = fields
      @permitted = permitted
      super("Unrecognized fields: #{fields.join(', ')}")
    end
  end


  rescue_from ActiveRecord::RecordNotFound do |_e|
    render json: { error: "Not found" }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { error: e.message, details: e.record&.errors&.full_messages }, status: :unprocessable_content
  end

  rescue_from NotAuthorizedError do |_e|
    render json: { error: "Forbidden" }, status: :forbidden
  end

  # Without this, a payload missing its root key (e.g. `{}` instead of
  # `{"evidence": {...}}`) escapes `params.require` uncaught and Rails
  # renders its default HTML error page — from a JSON API. Every controller
  # here using `params.require` was affected. 400 per docs/api/errors.md:
  # "Returned when a required parameter is missing."
  rescue_from ActionController::ParameterMissing do |e|
    render json: { error: "Missing required parameter: #{e.param}" }, status: :bad_request
  end

  # #1023 — the same failure the handler above exists for, from a different
  # direction. Rails ENUM assignment raises ArgumentError immediately, before
  # validation runs, so no validation error is ever produced to render: an
  # invalid `evidence_type` returned 500 and Rails' HTML error page, from a JSON
  # API. `Evidence` was the only model using enums; every other constrained
  # field uses `validates :inclusion` and already answered 422.
  #
  # Rescued at the base rather than in one controller so a future enum cannot
  # reintroduce it. Rails' own message — "'bogus' is not a valid evidence_type"
  # — is already what the caller needs.
  #
  # Logged at warn as well: an ArgumentError that is NOT bad input is a real
  # bug, and turning every one of them into a quiet 422 would hide it.
  rescue_from ArgumentError do |e|
    Rails.logger.warn(
      "[SPARC] ArgumentError reached the API boundary and was rendered as 422: #{e.message}"
    )
    render json: {
      error: "The request contained a value this endpoint does not accept.",
      details: [ e.message ]
    }, status: :unprocessable_content
  end

  # #995 — a field this endpoint does not accept is refused, not discarded.
  #
  # `params.permit` drops what it does not recognise, silently and by design,
  # and `action_on_unpermitted_parameters` is `false`, so a caller who misspells
  # a field gets 200 and a resource that did not change. "Nothing to do" and
  # "I did not understand you" arrive as the same response, which is the shape
  # #994 was filed for — there it produced `200 {"status":"updated"}` for a body
  # the endpoint had never parsed.
  #
  # The check lives here rather than in `config.action_controller.
  # action_on_unpermitted_parameters` because that setting is global: flipping
  # it to `:raise` would change how every web form is handled too, and toggling
  # it per request is not safe across Puma's threads.
  rescue_from UnrecognizedFields do |e|
    render json: {
      error: "The request body contained fields this endpoint does not accept. Nothing was changed.",
      details: e.fields.map { |field| "Unrecognized field: #{field}" },
      expected: e.permitted
    }, status: :unprocessable_content
  end

  private

  # Keys a client may send that are never part of a resource's attributes.
  # `format` is a routing artefact rather than a field, so it is not the
  # caller's mistake. `id` is deliberately NOT here: exempting it would mean a
  # request could name a primary key and be told nothing, while the neighbouring
  # `control_family_id` in the same body was refused. A caller echoing back a
  # resource it read is not rescued by the exemption anyway — `created_at`,
  # `updated_at` and `slug` are refused with or without it.
  ALWAYS_ALLOWED_FIELDS = %w[format].freeze

  # `params.require(root).permit(*filters)`, except that anything permit would
  # have dropped is reported instead. Returns the permitted parameters, so call
  # sites read the same as the ones they replaced.
  # `also_accepts:` names fields the endpoint genuinely consumes OUTSIDE the
  # permit list — read straight off the raw params by the action, the way
  # `back_matter_resource[source]` and `federation_peer[service_token]` are.
  # They are part of the endpoint's contract, so refusing them would be wrong;
  # they simply are not mass-assigned. Nothing else may be sent.
  # `nested` absorbs the hash-shaped filters (`public_metadata: {}`,
  # `attestations_attributes: [...]`) that would otherwise be read as unknown
  # keyword arguments once `also_accepts:` made this method take keywords.
  def permit_strictly(root, *filters, also_accepts: [], **nested)
    filters += [ nested ] if nested.any?

    scope = params.require(root)
    permitted = scope.permit(*filters)

    submitted = scope.respond_to?(:to_unsafe_h) ? scope.to_unsafe_h.keys.map(&:to_s) : []
    accepted  = permitted.to_h.keys.map(&:to_s)
    unknown   = submitted - accepted - also_accepts.map(&:to_s) - ALWAYS_ALLOWED_FIELDS

    raise UnrecognizedFields.new(unknown, expected_fields(filters) + also_accepts.map(&:to_s)) if unknown.any?

    permitted
  end

  # The filter list rendered as names a caller can act on. A nested filter
  # (`props: []`, `metadata: {}`) is named by its key.
  def expected_fields(filters)
    filters.flat_map do |filter|
      filter.is_a?(Hash) ? filter.keys.map(&:to_s) : filter.to_s
    end
  end

  # Resolve pagination size from request params (?items=N or ?per_page=N),
  # falling back to the per-endpoint default. Clamped to a hard ceiling to
  # prevent ?items=999999 from triggering a giant ActiveRecord query (#549).
  MAX_PAGINATION_LIMIT = 200

  def paginate(scope, items: 25)
    per_page = resolve_pagination_size(default: items)
    pagy, records = pagy(:offset, scope, limit: per_page)
    {
      data: records,
      meta: {
        page: pagy.page,
        pages: pagy.pages,
        count: pagy.count,
        items: pagy.limit
      }
    }
  end

  # #1019 — the envelope for a collection returned WHOLE.
  #
  # Some collections are not paginated, and should not be: a fixed set of user
  # guides, the KSI themes, the remediation-timeline grid, a promotion queue
  # filtered in memory by what the caller may approve. They were returning
  # `{data: [...]}` with no `meta` at all, or with `meta` carrying only a count,
  # so a client could not use one pagination helper across the API — and
  # `ksi_catalog#mappings` returned a DIFFERENT meta shape when its collection
  # was empty than when it was populated, which breaks a client precisely in the
  # case least likely to be tested.
  #
  # `page: 1, pages: 1` is not a fiction here: the whole collection is in this
  # response, so there is exactly one page of it.
  def whole_collection(rows, **extra)
    { page: 1, pages: 1, count: rows.size, items: rows.size }.merge(extra)
  end

  def resolve_pagination_size(default:)
    raw = params[:items].presence || params[:per_page].presence
    return default if raw.blank?

    n = raw.to_i
    return default if n <= 0

    [ n, MAX_PAGINATION_LIMIT ].min
  end

  # Shared OSCAL metadata and back-matter serialization for document APIs.
  # Call from serialize_document to append published, metadata_extra, and
  # back_matter_resources to any document response hash.
  def append_oscal_fields(data, doc, detailed: false)
    data[:published] = doc.try(:published)
    data[:back_matter_resources_count] = doc.respond_to?(:back_matter_resources) ? doc.back_matter_resources.count : 0

    if detailed
      data[:oscal_metadata] = doc.try(:metadata_extra) || {}
      if doc.respond_to?(:back_matter_resources)
        data[:back_matter_resources] = doc.back_matter_resources.order(:title).map do |r|
          serialize_back_matter_resource(r)
        end
      end
    end

    data
  end

  def serialize_back_matter_resource(resource, detailed: false)
    data = {
      id: resource.id,
      uuid: resource.uuid,
      title: resource.title,
      rel: resource.rel,
      media_type: resource.media_type,
      href: resource.href,
      source: resource.source,
      globally_available: resource.globally_available,
      organization_id: resource.organization_id,
      created_at: resource.created_at.iso8601,
      updated_at: resource.updated_at.iso8601
    }

    if detailed
      # #1039 — provenance and lifecycle. These belong to the DETAILED shape
      # only. They were first added to the compact block with the note "additive
      # keys: nothing existing changes shape", which is wrong: this serializer is
      # shared, the compact form is the one embedded in every document's
      # `back_matter_resources` array, and its published contract forbids extra
      # properties. Adding a key there breaks four endpoints that have nothing to
      # do with authoritative sources.
      data[:organization_name] = resource.organization&.name
      data[:provided_by_team] = resource.provided_by_team
      data[:provided_by_contact] = resource.provided_by_contact
      data[:archived] = resource.archived?
      data[:archived_at] = resource.archived_at&.iso8601
      data[:description] = resource.description
      data[:resource_data] = resource.resource_data
      data[:evidence_id] = resource.evidence_id
      data[:resourceable_type] = resource.resourceable_type
      data[:resourceable_id] = resource.resourceable_id
      data[:linked_controls] = resource.control_back_matter_links.map do |link|
        { type: link.linkable_type, id: link.linkable_id }
      end
    end

    data
  end

  # Provide audit_log helper since we're not inheriting from ApplicationController.
  # Uses AuditEvent.log which handles polymorphic subject extraction.
  #
  # #567 — the rescue used to silently swallow every AuditEvent failure
  # (including validation failures from unregistered action names),
  # which meant compliance bugs landed in prod with no signal at all.
  # Now: re-raise in dev / test so specs catch missing-action bugs
  # immediately; in prod still rescue + log so a runtime audit-log
  # outage doesn't take down API requests.
  def audit_log(action, subject: nil, metadata: {})
    AuditEvent.log(
      action: action,
      user: current_user,
      subject: subject,
      metadata: metadata,
      ip_address: request.remote_ip
    )
  rescue => e
    Rails.logger.warn("Audit log failed: #{e.message}")
    raise unless Rails.env.production?
  end

  # #618 — A metadata-only API create has no file in Active Storage, so the
  # DocumentConversionJob the UI/upload path enqueues never runs (and would
  # fail if it did — there is nothing to parse). Without this, the record sits
  # in the schema-default `pending` forever: the "stuck document" bug. Resolve
  # a fileless create to the terminal `completed` status on save so callers and
  # the UI see a definitive state. File-bearing paths (UI uploads, /convert)
  # keep pending + enqueue/parse and are untouched (guarded by file.attached?).
  #
  # NIST: SI-11 (Error Handling) — no silent indefinite-pending state.
  def finalize_unprocessed_create(doc)
    return unless doc.respond_to?(:status) && doc.respond_to?(:pending?)
    return if doc.respond_to?(:file) && doc.file.attached?
    return unless doc.pending?

    doc.update!(status: "completed")
    Rails.logger.info(
      "[DocumentLifecycle] event=completed reason=metadata_only_create " \
      "document_type=#{doc.class.name} document_id=#{doc.id} job_id=none"
    )
  end
end
