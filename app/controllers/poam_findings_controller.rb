# Admin UI for OSCAL POA&M findings (#423).
#
# A formal finding rolls up one or more observations + associated risks
# into a tracked compliance issue. SPARC's PoamItem typically points at
# at least one finding via the PoamItemFinding join.
class PoamFindingsController < ApplicationController
  include OscalExtensibilityParams

  before_action :set_poam_document
  before_action :set_poam_finding, only: %i[edit update destroy]

  def new
    @poam_finding = @poam_document.poam_findings.build
  end

  def create
    @poam_finding = @poam_document.poam_findings.build(poam_finding_params)
    @poam_finding.uuid ||= SecureRandom.uuid

    if @poam_finding.save
      audit_log("poam_finding_created", subject: @poam_finding,
                metadata: { title: @poam_finding.title, poam_document_id: @poam_document.id })
      flash[:success] = "Finding added"
      redirect_to poam_document_path(@poam_document)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Empty action: renders edit.html.erb; the record is loaded by a set_* before_action.
  end

  def update
    if @poam_finding.update(poam_finding_params)
      audit_log("poam_finding_updated", subject: @poam_finding, metadata: { title: @poam_finding.title })
      flash[:success] = "Finding updated"
      redirect_to poam_document_path(@poam_document)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @poam_finding.title
    audit_log("poam_finding_deleted", subject: @poam_finding, metadata: { title: title })
    @poam_finding.destroy
    flash[:success] = "Finding \"#{title}\" removed"
    redirect_to poam_document_path(@poam_document)
  end

  private

  def set_poam_document
    @poam_document = PoamDocument.find_by!(slug: params[:poam_document_id])
  end

  def set_poam_finding
    @poam_finding = @poam_document.poam_findings.find(params[:id])
  end

  def poam_finding_params
    permitted = params.require(:poam_finding).permit(
      :title, :description, :remarks, :implementation_statement_uuid,
      props_data:   [ :name, :value, :class, :ns, :uuid, :remarks ],
      links_data:   [ :href, :rel, :media_type, :text ],
      origins_data: [ :actor_type, :actor_uuid, :role_id ],
      # Form posts target as a flat hash with hyphenated/nested keys that
      # match the OSCAL schema directly (target.type, target.target-id,
      # target.status.state, target.status.remarks).
      target_data: [ :type, :"target-id", { status: %i[state remarks] } ]
    )
    permitted[:props_data]   = compact_props(permitted[:props_data])     if permitted.key?(:props_data)
    permitted[:links_data]   = compact_links(permitted[:links_data])     if permitted.key?(:links_data)
    permitted[:origins_data] = compact_origins(permitted[:origins_data]) if permitted.key?(:origins_data)
    permitted[:target_data]  = compact_target(permitted[:target_data])   if permitted.key?(:target_data)
    permitted
  end

  # Drop blank fields and the entire status sub-hash if state is empty,
  # so partially-filled targets don't render as `{ status: {} }` in the
  # exported OSCAL (which would still fail schema validation).
  def compact_target(target)
    return target if target.blank?

    raw = (target.respond_to?(:to_unsafe_h) ? target.to_unsafe_h : target.to_h)
            .deep_stringify_keys
            .reject { |_, v| v.blank? && !v.is_a?(Hash) }

    if raw["status"].is_a?(Hash)
      status = raw["status"].reject { |_, v| v.to_s.strip.empty? }
      if status["state"].present?
        raw["status"] = status
      else
        raw.delete("status")
      end
    end

    raw
  end
end
