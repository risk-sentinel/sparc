# Admin UI for OSCAL POA&M remediation milestones (#423).
#
# A milestone belongs to a `PoamRemediation` and tracks a discrete step
# in executing that remediation (e.g., "patch deployed to staging",
# "passed regression test"). No `origins_data` per OSCAL schema — only
# props and links.
class PoamMilestonesController < ApplicationController
  include OscalExtensibilityParams

  before_action :set_poam_document
  before_action :set_poam_remediation
  before_action :set_poam_milestone, only: %i[edit update destroy]

  def new
    @poam_milestone = @poam_remediation.poam_milestones.build
  end

  def create
    @poam_milestone = @poam_remediation.poam_milestones.build(poam_milestone_params)
    @poam_milestone.uuid ||= SecureRandom.uuid

    if @poam_milestone.save
      audit_log("poam_milestone_created", subject: @poam_milestone,
                metadata: { title: @poam_milestone.title, poam_remediation_id: @poam_remediation.id })
      flash[:success] = "Milestone added"
      redirect_to poam_document_path(@poam_document)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Empty action: renders edit.html.erb; the record is loaded by a set_* before_action.
  end

  def update
    if @poam_milestone.update(poam_milestone_params)
      audit_log("poam_milestone_updated", subject: @poam_milestone,
                metadata: { title: @poam_milestone.title })
      flash[:success] = "Milestone updated"
      redirect_to poam_document_path(@poam_document)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @poam_milestone.title
    audit_log("poam_milestone_deleted", subject: @poam_milestone, metadata: { title: title })
    @poam_milestone.destroy
    flash[:success] = "Milestone \"#{title}\" removed"
    redirect_to poam_document_path(@poam_document)
  end

  private

  def set_poam_document
    @poam_document = PoamDocument.find_by!(slug: params[:poam_document_id])
  end

  def set_poam_remediation
    @poam_remediation = PoamRemediation.joins(:poam_risk)
                                        .where(poam_risks: { poam_document_id: @poam_document.id })
                                        .find(params[:poam_remediation_id])
  end

  def set_poam_milestone
    @poam_milestone = @poam_remediation.poam_milestones.find(params[:id])
  end

  def poam_milestone_params
    permitted = params.require(:poam_milestone).permit(
      :title, :description, :due_date, :milestone_type, :remarks,
      props_data: [ :name, :value, :class, :ns, :uuid, :remarks ],
      links_data: [ :href, :rel, :media_type, :text ]
    )
    permitted[:props_data] = compact_props(permitted[:props_data]) if permitted.key?(:props_data)
    permitted[:links_data] = compact_links(permitted[:links_data]) if permitted.key?(:links_data)
    permitted
  end
end
