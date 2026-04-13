module OscalMetadata
  extend ActiveSupport::Concern

  included do
    before_update :enforce_oscal_uuid_immutability
  end

  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  METADATA_EXTRA_KEYS = %w[
    roles parties responsible-parties revisions props links document-ids
    locations remarks
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

  # Build the OSCAL metadata hash for export.
  # Includes all required fields (title, version, oscal-version, last-modified)
  # plus all optional fields stored in metadata_extra (revisions, document-ids,
  # responsible-parties, props, links, locations, remarks).
  #
  # Options:
  #   default_version: fallback version string (default: "1.0.0")
  #   default_roles: array of default role hashes
  #   default_parties: array of default party hashes
  def build_oscal_metadata(default_version: "1.0.0", default_roles: nil, default_parties: nil)
    base = {
      "title"         => name,
      "version"       => oscal_document_version || default_version,
      "oscal-version" => oscal_version || DEFAULT_OSCAL_VERSION,
      "last-modified" => updated_at&.iso8601 || Time.current.iso8601
    }

    # Include published timestamp if available
    if respond_to?(:published) && published.present?
      base["published"] = published.is_a?(String) ? published : published.iso8601
    end

    # Merge all stored metadata_extra fields
    extra = metadata_extra || {}
    if extra.any?
      merged = base.merge(extra)
    else
      defaults = default_oscal_metadata_extras
      defaults["roles"] = default_roles if default_roles.present?
      defaults["parties"] = default_parties if default_parties.present?
      merged = base.merge(defaults)
    end

    merged
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

  # Regenerate the document UUID after a content change.
  # Per OSCAL spec, every content modification must produce a new root UUID
  # and an updated last-modified timestamp.  The last-modified is handled
  # dynamically at export time (Time.current.iso8601), but the UUID is
  # persisted and must be explicitly regenerated.
  #
  # Uses update_column to bypass the enforce_oscal_uuid_immutability
  # callback, which is designed to prevent accidental overwrites during
  # normal attribute assignment — not intentional regeneration.
  def regenerate_oscal_uuid!
    return unless persisted? && self.class.column_names.include?("uuid")
    update_column(:uuid, SecureRandom.uuid)
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
