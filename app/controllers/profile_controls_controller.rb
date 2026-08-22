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
      save_param_values
      audit_log("profile_control_created", subject: @profile_control, metadata: { control_id: @profile_control.control_id, profile_document_id: @profile_document.id })
      flash[:success] = "Control #{@profile_control.control_id} added to profile"
      redirect_to profile_document_path(@profile_document)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_available_resources
  end

  def update
    if @profile_control.update(profile_control_params)
      save_editable_fields
      save_param_values
      audit_log("profile_control_updated", subject: @profile_control, metadata: { control_id: @profile_control.control_id })
      flash[:success] = "Control #{@profile_control.control_id} updated"
      redirect_to profile_document_path(@profile_document)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # PATCH /profile_documents/:id/profile_controls/:id/parameters  (#997)
  #
  # The tailoring write the Profile screen offers inline. It goes through
  # BaselineParameterService — the same service the Api::V1 endpoint uses — so
  # the web form and the API agree on what a valid tailoring decision is, and
  # the #994 guards (unknown ids named, a non-array selection refused) apply to
  # both. `save_param_values` on the full edit form writes any id it is handed;
  # this path does not.
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

  def save_param_values
    (params[:param_values] || {}).each do |param_id, value|
      field = @profile_control.profile_control_fields.find_or_initialize_by(
        field_name: "parameter:#{param_id}"
      )
      field.field_value = value.to_s.strip
      field.save!
    end
  end

  def load_available_resources
    @linked_resources = @profile_control.back_matter_resources.order(:title)
    org = current_user.organizations.first
    @available_resources = if org
      BackMatterResource.org_available(org.id)
                         .where.not(id: @linked_resources.select(:id))
                         .order(:title)
    else
      BackMatterResource.globally_available
                         .where.not(id: @linked_resources.select(:id))
                         .order(:title)
    end
  end
end
