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
#
# Controllers may override `before_publish_lifecycle(doc)` to run custom logic
# (e.g., Profile generates a resolved catalog) after validation but before
# the lifecycle transition. Return `{ error: "message" }` to abort publication.
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

    # Run any controller-specific pre-publish logic (e.g., Profile resolved catalog)
    hook_result = before_publish_lifecycle(doc)
    if hook_result.is_a?(Hash) && hook_result[:error]
      flash[:error] = hook_result[:error]
      redirect_to config[:redirect_path] and return
    end

    auto_increment_version!(doc)
    doc.publish_lifecycle!
    version = doc.oscal_document_version
    audit_log(config[:audit_event], subject: doc,
              metadata: { name: doc.name, lifecycle_status: "published", version: version })
    flash[:success] = "#{config[:label]} published successfully as version #{version}."
    redirect_to config[:redirect_path]
  end

  private

  # Hook for controllers to run custom logic before publication.
  # Return nil to proceed, or { error: "message" } to abort.
  def before_publish_lifecycle(_doc)
    nil
  end

  # Auto-increment or initialize the document's version on publish.
  # - Blank/nil → "1.0.0"
  # - Semantic version (e.g., "1.0.0") → increment patch (e.g., "1.0.1")
  # - Free-text version → left unchanged
  def auto_increment_version!(doc)
    column = version_column_for(doc)
    return unless column

    current = doc.send(column)
    new_version = if current.blank?
                    "1.0.0"
                  elsif current.match?(/\A\d+\.\d+\.\d+\z/)
                    parts = current.split(".")
                    parts[-1] = (parts[-1].to_i + 1).to_s
                    parts.join(".")
                  end

    doc.update_column(column, new_version) if new_version
  end

  # Detect the version column name for a document model.
  def version_column_for(doc)
    %w[ssp_version sar_version sap_version poam_version cdef_version profile_version version].find do |col|
      doc.class.column_names.include?(col)
    end
  end

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
