module OscalMetadata
  extend ActiveSupport::Concern

  included do
    before_update :enforce_oscal_uuid_immutability
  end

  OSCAL_VERSION = "1.1.2"

  METADATA_EXTRA_KEYS = %w[
    roles parties responsible-parties revisions props links document-ids
  ].freeze

  # Read helpers for metadata_extra sub-fields
  METADATA_EXTRA_KEYS.each do |key|
    method_name = "oscal_#{key.tr('-', '_')}"
    define_method(method_name) do
      (metadata_extra || {})[key] || []
    end
  end

  # Write helpers to update individual metadata_extra sub-fields
  METADATA_EXTRA_KEYS.each do |key|
    method_name = "oscal_#{key.tr('-', '_')}="
    define_method(method_name) do |value|
      self.metadata_extra = (metadata_extra || {}).merge(key => value)
    end
  end

  # Unified version accessor regardless of document type
  def oscal_document_version
    respond_to?(:ssp_version)     ? ssp_version :
    respond_to?(:sar_version)     ? sar_version :
    respond_to?(:sap_version)     ? sap_version :
    respond_to?(:poam_version)    ? poam_version :
    respond_to?(:cdef_version)    ? cdef_version :
    respond_to?(:profile_version) ? profile_version : nil
  end

  # Build the OSCAL metadata hash for export
  def build_oscal_metadata
    base = {
      "title"         => name,
      "version"       => oscal_document_version || "1.0.0",
      "oscal-version" => oscal_version || OSCAL_VERSION,
      "last-modified" => Time.current.iso8601
    }

    extra = metadata_extra || {}
    if extra.any?
      base.merge(extra)
    else
      base.merge(default_oscal_metadata_extras)
    end
  end

  # Merge metadata from a parent/source document (inheritance)
  # Child fields take precedence over parent fields.
  def inherit_metadata_from(source)
    return unless source.respond_to?(:metadata_extra)

    parent_extra = source.metadata_extra || {}
    child_extra  = self.metadata_extra || {}

    merged = {}
    METADATA_EXTRA_KEYS.each do |key|
      parent_val = parent_extra[key]
      child_val  = child_extra[key]

      merged[key] = if child_val.present?
        child_val
      elsif parent_val.present?
        deep_copy(parent_val)
      end
    end

    # Merge array fields (roles, parties) by combining unique entries
    %w[roles parties].each do |key|
      if parent_extra[key].is_a?(Array) && child_extra[key].is_a?(Array)
        merged[key] = merge_unique_entries(parent_extra[key], child_extra[key], key == "roles" ? "id" : "uuid")
      end
    end

    self.metadata_extra = merged.compact
  end

  # Assign the OSCAL UUID from an imported document. If the source document
  # had a UUID, use it; otherwise keep the Postgres-generated default.
  def assign_oscal_uuid!(source_uuid)
    return if source_uuid.blank?

    update_column(:uuid, source_uuid) if persisted?
  end

  # Build an OSCAL-compliant back-matter resource identifying SPARC as the
  # document manager. Appended to every export for auditor traceability.
  def sparc_back_matter_resource
    {
      "uuid"        => SecureRandom.uuid,
      "title"       => "SPARC Document Source",
      "description" => "Managed by #{SparcConfig.app_name}",
      "rlinks"      => [
        { "href" => SparcConfig.app_url, "media-type" => "text/html" }
      ]
    }
  end

  # Build the OSCAL back-matter hash for export. Merges preserved resources
  # from import_metadata with the SPARC-identifying resource.
  def build_oscal_back_matter
    preserved = import_metadata&.dig("back_matter") || []
    resources = preserved + [ sparc_back_matter_resource ]
    { "resources" => resources }
  end

  private

  def enforce_oscal_uuid_immutability
    return unless respond_to?(:uuid) && respond_to?(:uuid_changed?)
    self.uuid = uuid_was if uuid_changed? && uuid_was.present?
  end

  def default_oscal_metadata_extras
    {
      "roles" => [ { "id" => "prepared-by", "title" => "Prepared By" } ],
      "parties" => [ {
        "uuid" => SecureRandom.uuid,
        "type" => "organization",
        "name" => "SPARC Export"
      } ]
    }
  end

  # Merge two arrays of hashes, deduplicating by a key field
  def merge_unique_entries(parent_arr, child_arr, key_field)
    combined = (parent_arr + child_arr)
    combined.uniq { |entry| entry[key_field] }
  end

  def deep_copy(obj)
    JSON.parse(obj.to_json)
  end
end
