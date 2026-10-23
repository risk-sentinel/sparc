class ProfileControlsController < ApplicationController
  before_action :set_profile_document
  # #919 — a profile's controls ARE the profile, so editing them is a
  # `profiles.write` act. Mirrors Api::V1::ProfileDocumentsController; unscoped
  # because profiles are instance-level, not boundary-scoped. Every action here
  # (new/create/edit/update/destroy) is authoring.
  before_action :authorize_profiles_write!
  before_action :set_profile_control, only: %i[edit update update_parameters destroy]
  # #1008 — the same unenforced rule as the API path. Both surfaces asked only
  # whether the caller may write profiles, never whether this profile is still
  # editable.
  before_action :refuse_published_profile!, only: %i[create update update_parameters destroy]

  def new
    @profile_control = @profile_document.profile_controls.build
  end

  def create
    @profile_control = @profile_document.profile_controls.build(profile_control_params)
    @profile_control.row_order = (@profile_document.profile_controls.maximum(:row_order) || 0) + 1

    if @profile_control.save
      save_editable_fields
      audit_log("profile_control_created", subject: @profile_control, metadata: { control_id: @profile_control.control_id, profile_document_id: @profile_document.id })
      flash[:success] = "Control #{@profile_control.control_id} added to profile"
      redirect_to profile_document_path(@profile_document)
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    load_available_resources
  end

  def update
    if @profile_control.update(profile_control_params)
      save_editable_fields
      audit_log("profile_control_updated", subject: @profile_control, metadata: { control_id: @profile_control.control_id })
      flash[:success] = "Control #{@profile_control.control_id} updated"
      redirect_to profile_document_path(@profile_document)
    else
      render :edit, status: :unprocessable_content
    end
  end

  # PATCH /profile_documents/:id/profile_controls/:id/parameters  (#997)
  #
  # The tailoring write the Profile screen offers inline. It goes through
  # BaselineParameterService — the same service the Api::V1 endpoint uses — so
  # the web form and the API agree on what a valid tailoring decision is, and
  # the #994 guards (unknown ids named, a non-array selection refused) apply to
  # both. (#1270 removed the Edit form's parameter table, whose
  # `save_param_values` wrote any id it was handed; this is now the only web
  # path that writes a parameter.)
  def update_parameters
    result = BaselineParameterService.new(@profile_document)
                                     .update_parameters(parameter_payload_from_form)

    audit_log("profile_control_updated", subject: @profile_control,
              metadata: { control_id: @profile_control.control_id,
                          action: "parameter_update",
                          parameters_updated: result[:parameters_updated],
                          selections_updated: result[:selections_updated] })

    if result[:validation_errors].any?
      flash[:error] = "Some values were not applied: " \
                      "#{result[:validation_errors].map { |e| e[:error] }.uniq.join('; ')}"
    else
      applied = result[:parameters_updated] + result[:selections_updated]
      flash[:success] = "#{@profile_control.display_id} — #{applied} " \
                        "#{'parameter'.pluralize(applied)} updated"
    end

    redirect_to profile_document_path(@profile_document, anchor: "control-#{@profile_control.id}")
  end

  # PATCH /profile_documents/:profile_document_id/profile_controls/bulk  (#1270)
  #
  # Sets the priority of, or links/unlinks a back-matter resource on, the
  # controls the user selected on the Profile screen. The inline priority
  # selector posts here too, as JSON, for one control. Writes through
  # ProfileControlBulkEditService, as PUT /api/v1/profile_documents/:id/controls/bulk does.
  def bulk
    args = bulk_args
    authorize_permission!("back_matter.write") if args[:link_resource_ids].present? || args[:unlink_resource_ids].present?

    result = ProfileControlBulkEditService.new(@profile_document, user: current_user).apply(**args)
    audit_log("profile_controls_bulk_edited", subject: @profile_document,
              metadata: { control_ids: result.control_ids, priority_changed: result.priority_changed,
                          priority: result.priority, linked: result.linked, unlinked: result.unlinked })

    respond_to do |format|
      format.json { render json: { data: result.to_h } }
      format.html do
        flash[:success] = bulk_summary(result)
        redirect_to profile_document_path(@profile_document)
      end
    end
  rescue ProfileControlBulkEditService::EditError => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_content }
      format.html do
        flash[:error] = e.message
        redirect_to profile_document_path(@profile_document)
      end
    end
  end

  def destroy
    control_id = @profile_control.control_id
    audit_log("profile_control_deleted", subject: @profile_control, metadata: { control_id: control_id })
    @profile_control.destroy
    flash[:success] = "Control #{control_id} removed from profile"
    redirect_to profile_document_path(@profile_document)
  end

  private

  # #1008 — see Api::V1::BaselineParametersController for the reasoning. Kept on
  # both surfaces because the invariant belongs to the document, not to one
  # client of it.
  def refuse_published_profile!
    return unless @profile_document.published_lifecycle?

    flash[:error] = "#{@profile_document.name} is published and cannot be edited. " \
                    "Duplicate it to create an editable draft."
    redirect_to profile_document_path(@profile_document)
  end

  def authorize_profiles_write!
    authorize_permission!("profiles.write")
  end

  def set_profile_document
    @profile_document = ProfileDocument.find_by!(slug: params[:profile_document_id])
  end

  def set_profile_control
    @profile_control = @profile_document.profile_controls.find(params[:id])
  end

  # The bulk bar names its action with the button pressed; the inline selector
  # and other JSON callers send the change itself, as the API does.
  def bulk_args
    args = { control_ids: params[:control_ids] }
    case params[:bulk_action]
    when "priority" then args[:priority] = params[:priority].to_s
    when "link"     then args[:link_resource_ids] = Array(params[:resource_id])
    when "unlink"   then args[:unlink_resource_ids] = Array(params[:resource_id])
    else
      args[:priority] = params[:priority].to_s if params.key?(:priority)
      args[:link_resource_ids] = Array(params[:link_resource_ids])
      args[:unlink_resource_ids] = Array(params[:unlink_resource_ids])
    end
    args
  end

  def bulk_summary(result)
    count = result.control_ids.size
    parts = []
    parts << "priority #{result.priority || 'cleared'}" if result.priority_changed
    parts << "#{result.linked} #{'link'.pluralize(result.linked)} added" if result.linked.positive?
    parts << "#{result.unlinked} #{'link'.pluralize(result.unlinked)} removed" if result.unlinked.positive?
    parts << "nothing changed" if parts.empty?
    "#{count} #{'control'.pluralize(count)}: #{parts.join(', ')}"
  end

  def profile_control_params
    params.require(:profile_control).permit(:control_id, :title, :priority)
  end

  def save_editable_fields
    (params[:fields] || {}).each do |field_name, value|
      next unless ProfileControlField::EDITABLE_FIELDS.include?(field_name.to_s)

      field = @profile_control.profile_control_fields.find_or_initialize_by(field_name: field_name.to_s)
      field.field_value = value.to_s.strip
      field.save!
    end
  end

  # A checkbox group posts an array and a text input posts a string, which is
  # exactly the parameter/selection split the service expects. A select with
  # nothing ticked still posts its hidden empty entry, so clearing an answer is
  # possible — without it the field would simply vanish from the payload and
  # the old value would silently stand.
  def parameter_payload_from_form
    payload = { parameters: [], selections: [] }

    (params[:param_values] || {}).each do |param_id, value|
      if value.is_a?(Array)
        payload[:selections] << {
          select_id: param_id.to_s,
          selected: value.map { |v| v.to_s.strip }.reject(&:blank?)
        }
      else
        payload[:parameters] << { param_id: param_id.to_s, value: value.to_s.strip }
      end
    end

    payload
  end

  def load_available_resources
    @linked_resources = @profile_control.back_matter_resources.order(:title)
    @available_resources = BackMatterResource.linkable_by(current_user)
                                             .where.not(id: @linked_resources.select(:id))
                                             .order(:title)
  end
end
