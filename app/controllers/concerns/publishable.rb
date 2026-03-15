# Shared publication logic for document controllers.
#
# Including controllers must define a private `publish_config` method returning:
#   {
#     document:      @ssp_document,        # the ActiveRecord document instance
#     audit_event:   "ssp_document_published",
#     redirect_path: ssp_document_path(@ssp_document),
#     label:         "SSP"
#   }
#
# Provides two actions:
#   - publish_check (GET)  — returns JSON readiness data for the smart modal
#   - publish       (PATCH) — validates metadata, applies inline fixes, publishes
module Publishable
  extend ActiveSupport::Concern

  # GET /documents/:id/publish_check.json
  # Returns metadata readiness data for the publication modal.
  def publish_check
    config = publish_config
    service = PublicationValidationService.new(config[:document], current_user: current_user)
    render json: service.publication_readiness
  end

  # PATCH /documents/:id/publish
  # Validates OSCAL metadata completeness, applies any inline fixes from the modal,
  # then transitions the document to published state.
  def publish
    config = publish_config
    doc = config[:document]

    # Apply inline metadata fixes from the publication modal
    apply_publish_metadata_fixes!(doc)

    service = PublicationValidationService.new(doc, current_user: current_user)
    result = service.validate

    unless result.valid?
      flash[:error] = "Cannot publish: #{result.errors.join('; ')}"
      redirect_to config[:redirect_path] and return
    end

    doc.publish_lifecycle!
    audit_log(config[:audit_event], subject: doc,
              metadata: { name: doc.name, lifecycle_status: "published" })
    flash[:success] = "#{config[:label]} published successfully."
    redirect_to config[:redirect_path]
  end

  private

  # Merge metadata fixes submitted from the publication modal into metadata_extra.
  # Accepts roles, parties, and responsible-parties arrays from params.
  def apply_publish_metadata_fixes!(doc)
    fixes = params[:metadata_fixes]
    return if fixes.blank?

    extra = doc.metadata_extra || {}

    if fixes[:roles].present?
      new_roles = JSON.parse(fixes[:roles]) rescue []
      existing = extra["roles"] || []
      merged = merge_by_key(existing, new_roles, "id")
      extra["roles"] = merged if merged.any?
    end

    if fixes[:parties].present?
      new_parties = JSON.parse(fixes[:parties]) rescue []
      existing = extra["parties"] || []
      merged = merge_by_key(existing, new_parties, "uuid")
      extra["parties"] = merged if merged.any?
    end

    if fixes[:responsible_parties].present?
      new_rps = JSON.parse(fixes[:responsible_parties]) rescue []
      existing = extra["responsible-parties"] || []
      merged = merge_by_key(existing, new_rps, "role-id")
      extra["responsible-parties"] = merged if merged.any?
    end

    doc.update!(metadata_extra: extra) if extra != doc.metadata_extra
  end

  # Merge two arrays of hashes, deduplicating by a key field.
  # New entries override existing entries with the same key.
  def merge_by_key(existing, new_entries, key)
    combined = {}
    existing.each { |e| combined[e[key]] = e }
    new_entries.each { |e| combined[e[key]] = e }
    combined.values
  end
end
