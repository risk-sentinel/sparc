class AuthorizationBoundariesController < ApplicationController
  include BulkDestroyable

  before_action :set_authorization_boundary, only: [
    :show, :edit, :update, :destroy,
    :ato_wizard, :create_ato_package, :download_ato_package
  ]
  # #629 — bulk delete is admin-only.
  before_action :authorize_admin!, only: [ :bulk_destroy ]

  def index
    @authorization_boundaries = AuthorizationBoundary.order(updated_at: :desc)
    @total_count = @authorization_boundaries.count
    @active_count = @authorization_boundaries.where(status: "active").count
    @member_count = AuthorizationBoundaryMembership.count
    @authorization_boundaries = @authorization_boundaries.search_text(params[:q]) # #672 — filter listed rows; tiles keep totals
  end

  def show
    @boundaries  = @authorization_boundary.boundaries.includes(:cdef_documents).order(:name)
    @memberships = @authorization_boundary.authorization_boundary_memberships.order(:role, :user_name)
    @summary     = @authorization_boundary.artifact_summary
  end

  def new
    @authorization_boundary = AuthorizationBoundary.new
  end

  def create
    @authorization_boundary = AuthorizationBoundary.new(authorization_boundary_params)

    if @authorization_boundary.save
      audit_log("authorization_boundary_created", subject: @authorization_boundary, metadata: { name: @authorization_boundary.name })
      flash[:success] = "Authorization boundary '#{@authorization_boundary.name}' created."
      redirect_to @authorization_boundary
    else
      flash.now[:error] = @authorization_boundary.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Empty action: renders edit.html.erb; the record is loaded by a set_* before_action.
  end

  def update
    metadata_or_profile_changed =
      authorization_boundary_params.key?(:boundary_metadata) ||
      authorization_boundary_params.key?(:profile_document_id)

    if @authorization_boundary.update(authorization_boundary_params)
      audit_log("authorization_boundary_updated", subject: @authorization_boundary, metadata: { name: @authorization_boundary.name })
      # #395 P3: when boundary-level metadata changes, propagate to all
      # linked documents in the background.
      BoundaryMetadataSyncJob.perform_later(@authorization_boundary.id) if metadata_or_profile_changed
      flash[:success] = "Authorization boundary updated."
      redirect_to @authorization_boundary
    else
      flash.now[:error] = @authorization_boundary.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @authorization_boundary.name
    # #629 — honor the referential-integrity guard: only flash success if the
    # destroy actually happened (previously it always claimed success + logged
    # the delete before attempting it).
    if @authorization_boundary.destroy
      audit_log("authorization_boundary_deleted", subject: @authorization_boundary, metadata: { name: name })
      flash[:success] = "Authorization boundary '#{name}' deleted."
      redirect_to authorization_boundaries_path
    else
      audit_log("authorization_boundary_delete_blocked", subject: @authorization_boundary,
        metadata: { name: name, reason: @authorization_boundary.errors.full_messages.join(", ") })
      flash[:error] = @authorization_boundary.errors.full_messages.join(", ")
      redirect_to @authorization_boundary
    end
  end

  # DELETE /authorization_boundaries/bulk_destroy (#629) — admin-only.
  def bulk_destroy
    perform_bulk_destroy(
      model_class:   AuthorizationBoundary,
      redirect_path: authorization_boundaries_path,
      label:         "authorization boundary"
    )
  end

  # ── ATO Package Wizard ─────────────────────────────────────────

  def ato_wizard
    @memberships = @authorization_boundary.authorization_boundary_memberships.order(:role)
    @profiles    = ProfileDocument.where(lifecycle_status: "published")
                                  .where.not(resolved_catalog_json: nil)
                                  .order(:name)
    @cdefs       = CdefDocument.where(status: "completed").order(:name)
    @ssps        = SspDocument.where(status: "completed").order(:name)
    @saps        = SapDocument.where(status: "completed").order(:name)
    @sars        = SarDocument.where(status: "completed").order(:name)
    @poams       = PoamDocument.where(status: "completed").order(:name)

    # Warn if required roles are missing
    roles = @memberships.pluck(:role)
    @missing_roles = []
    @missing_roles << "System Owner" unless roles.include?("system_owner")
    @missing_roles << "Authorizing Official" unless roles.include?("authorizing_official")
  end

  def create_ato_package
    service = AtoPackageService.new(@authorization_boundary, ato_package_params)
    service.create

    audit_log("ato_package_created", subject: @authorization_boundary,
      metadata: { name: @authorization_boundary.name })

    flash[:success] = "ATO package built for '#{@authorization_boundary.name}'."
    redirect_to authorization_boundary_path(@authorization_boundary)
  rescue StandardError => e
    flash[:error] = "Error building ATO package: #{e.message}"
    redirect_to ato_wizard_authorization_boundary_path(@authorization_boundary)
  end

  def download_ato_package
    service = AtoPackageExportService.new(@authorization_boundary)
    zip_data = service.generate_zip

    audit_log("ato_package_exported", subject: @authorization_boundary,
      metadata: { name: @authorization_boundary.name })

    send_data zip_data,
              filename: "#{@authorization_boundary.name}_ato_package_#{Date.today}.zip",
              type: "application/zip",
              disposition: "attachment"
  end

  private

  def set_authorization_boundary
    @authorization_boundary = AuthorizationBoundary.find_by!(slug: params[:id])
  end

  def authorization_boundary_params
    params.require(:authorization_boundary).permit(
      :name, :description, :status, :authorization_boundary_description,
      :profile_document_id,                                       # #395 P3
      boundary_metadata: AuthorizationBoundary::BOUNDARY_METADATA_KEYS  # #395 P3
    )
  end

  def ato_package_params
    params.permit(
      :profile_mode, :profile_document_id,
      :cdef_mode,
      :ssp_mode, :ssp_document_id, :ssp_name, :ssp_description,
      :system_status, :security_sensitivity_level,
      :security_objective_confidentiality, :security_objective_integrity,
      :security_objective_availability, :authorization_boundary_description,
      :sap_mode, :sap_document_id, :sap_name, :sap_description,
      :assessment_type, :assessment_start, :assessment_end,
      :sar_mode, :sar_document_id, :sar_name, :sar_description,
      :sar_assessment_start, :sar_assessment_end,
      :poam_mode, :poam_document_id, :poam_name, :poam_description,
      cdef_document_ids: []
    )
  end
end
