# Bulk imports BackMatterResource records from a JSON array. Used by the
# /api/v1/back_matter_resources/bulk endpoint and (eventually) by the
# CSV-converted-to-JSON workflow that the SPARC support team runs.
#
# Per-row results are returned so the caller can reconcile partial
# successes. Validation errors on a single row do not abort the batch.
#
# NIST AU-2 / AU-3: each successful insert appends a "create" change row
# tagged with the shared batch_uuid for the bulk operation, so the audit
# trail can be traced back to one bulk request.
class BackMatterBulkImportService
  MAX_ENTRIES_INLINE = 500

  Result = Struct.new(:success, :batch_uuid, :imported, :skipped, :errors,
                      :status_code, :error, keyword_init: true) do
    def success? = success
  end

  def initialize(entries:, actor:, organization: nil)
    @entries      = Array(entries)
    @actor        = actor
    @organization = organization
    @batch        = SecureRandom.uuid
    @imported     = []
    @skipped      = []
    @errors       = []
  end

  def call
    return too_large_result if @entries.size > MAX_ENTRIES_INLINE
    return empty_result      if @entries.empty?

    BackMatterResource.transaction do
      @entries.each_with_index { |entry, idx| process_entry(entry, idx) }
    end

    Result.new(success: true, batch_uuid: @batch, imported: @imported,
               skipped: @skipped, errors: @errors)
  end

  private

  def process_entry(entry, idx)
    unless entry.is_a?(Hash) || entry.respond_to?(:to_unsafe_h)
      @errors << { index: idx, error: "Entry must be an object" }
      return
    end

    attrs = (entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry).deep_symbolize_keys
    title = attrs[:title].to_s.strip
    if title.empty?
      @errors << { index: idx, error: "title is required" }
      return
    end

    if (existing = dedup_match(attrs))
      @skipped << { index: idx, id: existing.id, reason: "duplicate (href + title)" }
      return
    end

    resource = BackMatterResource.create!(
      uuid:               SecureRandom.uuid,
      title:              title,
      description:        attrs[:description],
      href:               attrs[:href],
      media_type:         attrs[:media_type],
      rel:                attrs[:rel].presence || "reference",
      source:             attrs[:source].presence || "managed",
      organization:       @organization,
      globally_available: attrs[:globally_available] == true,
      resource_data:      attrs[:resource_data] || {}
    )

    BackMatterResourceChange.create!(
      back_matter_resource: resource,
      changed_by_user:      @actor,
      change_type:          "create",
      field:                "bulk_import",
      from_value:           nil,
      to_value:             "1",
      batch_uuid:           @batch,
      changed_at:           Time.current
    )

    @imported << resource
  rescue ActiveRecord::RecordInvalid => e
    @errors << { index: idx, error: e.record.errors.full_messages.join(", ") }
  end

  def dedup_match(attrs)
    return nil if attrs[:href].blank?

    BackMatterResource.where(organization_id: @organization&.id)
                      .where(href: attrs[:href], title: attrs[:title])
                      .first
  end

  def too_large_result
    Result.new(success: false, status_code: :unprocessable_entity,
               error: "Bulk imports limited to #{MAX_ENTRIES_INLINE} entries; " \
                      "split larger batches and resubmit")
  end

  def empty_result
    Result.new(success: false, status_code: :unprocessable_entity,
               error: "No entries provided")
  end
end
