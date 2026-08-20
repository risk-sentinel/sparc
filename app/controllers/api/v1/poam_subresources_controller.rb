# frozen_string_literal: true

# #1010 — shared base for the POA&M sub-objects.
#
# #832 gave `poam_risks` an API and left its six siblings behind — items,
# remediations, milestones, observations, findings and local components. Those
# are the substance of a POA&M: they are what OSCAL exports, so a POA&M could be
# assembled through the API only in part. Found by the missing-endpoint axis of
# #995.
#
# Six resources, one shape. Each subclass declares its model, its parameter key
# and its permitted fields; everything else — nesting, authorization, audit,
# serialization of the shared OSCAL arrays — lives here. The alternative was six
# near-identical controllers, which is how the six of them came to disagree in
# the web layer in the first place.
#
# AUTHORIZATION is `poam.write`, scoped to the parent document's authorization
# boundary, mirroring PoamChildAuthorization. A document with no boundary
# requires an instance-level grant, which is the fail-closed direction: an
# unassociated document must not be editable by anyone who merely holds the
# permission somewhere.
#
# NIST 800-53 Controls:
#   CA-5 Plan of Action and Milestones, AC-3 Access Enforcement,
#   AU-12 Audit Record Generation
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::PoamSubresourcesController < Api::V1::BaseController
  # Shared OSCAL array shapes. Every sub-object carries some subset; declaring
  # them once keeps a field from being permitted on one resource and silently
  # dropped on its sibling.
  PROPS_SHAPE   = { props_data: [ :name, :value, :class, :ns, :uuid, :remarks ] }.freeze
  LINKS_SHAPE   = { links_data: [ :href, :rel, :media_type, :text ] }.freeze
  ORIGINS_SHAPE = { origins_data: [ :actor_type, :actor_uuid, :role_id ] }.freeze

  before_action :set_document
  before_action :authorize_poam_read!,  only: %i[index show]
  before_action :authorize_poam_write!, only: %i[create update destroy]
  before_action :set_record, only: %i[show update destroy]

  def index
    result = paginate(collection.order(:id), items: 50)

    render json: {
      data: result[:data].map { |record| serialize(record) },
      meta: result[:meta]
    }
  end

  def show
    render json: { data: serialize(@record, detailed: true) }
  end

  def create
    record = build_record
    # Each of the six web controllers assigns this by hand in its own `create`.
    # It belongs in one place: an OSCAL sub-object without a uuid is not
    # exportable, and six copies of a rule is six chances to omit it.
    record.uuid ||= SecureRandom.uuid if record.respond_to?(:uuid)
    record.save!

    audit_log("#{audit_prefix}_created", subject: record,
              metadata: audit_metadata(record))
    render json: { data: serialize(record, detailed: true) }, status: :created
  end

  def update
    @record.update!(record_params)

    audit_log("#{audit_prefix}_updated", subject: @record,
              metadata: audit_metadata(@record))
    render json: { data: serialize(@record, detailed: true) }
  end

  def destroy
    audit_log("#{audit_prefix}_deleted", subject: @record,
              metadata: audit_metadata(@record))
    @record.destroy!

    render json: { data: { id: @record.id, deleted: true } }
  end

  private

  # ── Subclass contract ────────────────────────────────────────────────────
  # Each subclass supplies these four. Anything else it overrides is a genuine
  # difference between the resources, not boilerplate.

  def model            = raise(NotImplementedError, "#{self.class} must declare a model")
  def param_key        = model.name.underscore.to_sym
  def permitted_fields = raise(NotImplementedError, "#{self.class} must declare permitted_fields")
  def collection       = @document.public_send(model.name.underscore.pluralize)

  def build_record = collection.new(record_params)

  def audit_prefix = model.name.underscore

  def audit_metadata(record)
    { poam_document_id: @document.id, title: record.try(:title) }
  end

  # ── Shared plumbing ──────────────────────────────────────────────────────

  # POA&M documents are slug-addressed in the web routes; an id works too.
  def set_document
    param = params[:poam_document_id].to_s
    @document = PoamDocument.find_by(slug: param) || PoamDocument.find(param)
  end

  def set_record
    @record = collection.find(params[:id])
  end

  def record_params
    permit_strictly(param_key, *permitted_fields)
  end

  def boundary_id = @document.authorization_boundary_id

  def authorize_poam_read!
    return if current_user.admin?
    return if current_user.has_permission?("poam.read", authorization_boundary_id: boundary_id)

    raise NotAuthorizedError, "Not authorized to view this POA&M"
  end

  def authorize_poam_write!
    return if current_user.admin?
    return if current_user.has_permission?("poam.write", authorization_boundary_id: boundary_id)

    raise NotAuthorizedError, "Not authorized to modify this POA&M"
  end

  # The OSCAL arrays are surfaced on the DETAILED view only. They are verbose
  # and a list of thirty items would otherwise be mostly markup.
  def serialize(record, detailed: false)
    data = {
      id: record.id,
      uuid: record.try(:uuid),
      title: record.try(:title),
      poam_document_id: @document.id
    }.merge(summary_fields(record))

    if detailed
      data[:description] = record.try(:description)
      data[:remarks] = record.try(:remarks)
      data.merge!(detail_fields(record))
      %i[props_data links_data origins_data methods_data].each do |field|
        data[field] = record.public_send(field) if record.respond_to?(field)
      end
      data[:created_at] = record.created_at.utc.iso8601
      data[:updated_at] = record.updated_at.utc.iso8601
    end

    data.compact
  end

  # Subclasses add the few fields that are theirs alone.
  def summary_fields(_record) = {}
  def detail_fields(_record)  = {}
end
