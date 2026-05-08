module OscalMetadata
  extend ActiveSupport::Concern

  included do
    before_update :enforce_oscal_uuid_immutability
    has_many :back_matter_resources, as: :resourceable, dependent: :destroy
  end

  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  # #395 P2: resolve an OSCAL `import-*.href` value to a SPARC document.
  # Only handles the `uuid:<...>` scheme — anchor placeholders (`#system-...`)
  # return nil so callers can fall back to boundary-sibling lookup (which
  # the BoundaryLinkInheritance concern already wires up).
  def self.resolve_import_href(href, target_class)
    return nil if href.blank?
    return nil unless href.to_s.start_with?("uuid:")
    target_class.find_by(uuid: href.to_s.delete_prefix("uuid:"))
  end

  # #395 P2: build the export-side `import-*.href` for a sibling document.
  # Returns nil when sibling is nil so callers can fall back to "#" (NIST
  # schema requires the field to be present even when unresolved).
  def self.import_href_for(sibling)
    return nil unless sibling.respond_to?(:uuid)
    sib_uuid = sibling.uuid
    sib_uuid.present? ? "uuid:#{sib_uuid}" : nil
  end

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
  # Parties declared in metadata_extra["parties"] — used by the origins
  # picker on POAM child entities (#416/#423) to resolve actor-uuid
  # references. Each party is `{ "uuid", "type", "name", ... }`.
  def oscal_parties
    Array(metadata_extra&.dig("parties"))
  end

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

    # Allowlist filter: METADATA_EXTRA_KEYS are the OSCAL spec metadata
    # fields. Anything else parked in metadata_extra (#451) — internal
    # SPARC bookkeeping like ProgressTrackable's processing_stage /
    # processing_message / processing_*_at, import_warnings, etc. —
    # is filtered out before export. OSCAL schemas reject additional
    # properties under metadata, so leaking these would fail validation.
    extra = (metadata_extra || {}).slice(*METADATA_EXTRA_KEYS)
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

  # Assign the OSCAL UUID from an imported document. Validates the UUID
  # format (RFC 4122 v4) and checks for collisions with existing documents
  # before assignment. On collision or invalid format, keeps the auto-generated
  # UUID and preserves the original in import_metadata for audit trail.
  #
  # NIST SI-10: Information Input Validation
  # NIST AU-10: Non-repudiation (UUID lineage)
  def assign_oscal_uuid!(source_uuid)
    return if source_uuid.blank?
    return unless persisted?

    uuid_col = self.class.column_names.include?("oscal_uuid") ? :oscal_uuid : :uuid

    # Check for collision with existing document of same type
    existing = self.class.where(uuid_col => source_uuid).where.not(id: id).first
    if existing
      store_replaced_uuid(source_uuid, collision_with: existing.id)
      Rails.logger.warn("[OSCAL UUID] Collision detected: #{source_uuid} already belongs to #{self.class.name}##{existing.id}. Assigned fresh UUID to #{self.class.name}##{id}.")
      return
    end

    # Validate RFC 4122 v4 format
    unless source_uuid.match?(BackMatterResource::UUID_V4_REGEX)
      store_replaced_uuid(source_uuid, reason: "non_rfc4122_format")
      Rails.logger.warn("[OSCAL UUID] Non-RFC 4122 v4 UUID detected: #{source_uuid}. Assigned fresh UUID to #{self.class.name}##{id}.")
      return
    end

    # Detect obvious placeholder/sequential UUIDs (e.g., a1b2c3d4-1111-4000-a000-000000000008)
    # These are technically valid v4 format but clearly not random.
    if placeholder_uuid?(source_uuid)
      store_replaced_uuid(source_uuid, reason: "placeholder_pattern")
      Rails.logger.warn("[OSCAL UUID] Placeholder UUID detected: #{source_uuid}. Assigned fresh UUID to #{self.class.name}##{id}.")
      return
    end

    update_column(uuid_col, source_uuid)
  end

  # Record that a source UUID was replaced during import, preserving
  # the original for audit trail and traceability.
  def store_replaced_uuid(original_uuid, collision_with: nil, reason: nil)
    meta = (import_metadata || {}).dup
    meta["original_uuid"] = original_uuid
    meta["uuid_replaced"] = true
    meta["uuid_collision_with"] = collision_with if collision_with
    meta["uuid_replace_reason"] = reason || "collision"
    update_column(:import_metadata, meta)
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
  # document manager. Uses a persistent UUID stored in import_metadata so
  # the same UUID is used across exports (traceability).
  def sparc_back_matter_resource
    uuid = import_metadata&.dig("sparc_resource_uuid")
    unless uuid
      uuid = SecureRandom.uuid
      if persisted?
        update_column(:import_metadata,
          (import_metadata || {}).merge("sparc_resource_uuid" => uuid))
      end
    end

    {
      "uuid"        => uuid,
      "title"       => "SPARC Document Source",
      "description" => "Managed by #{SparcConfig.app_name}",
      "rlinks"      => [
        { "href" => SparcConfig.app_url, "media-type" => "text/html" }
      ]
    }
  end

  # Build the OSCAL back-matter hash for export. Merges managed resources,
  # imported resources (deduplicated), and the SPARC identifier resource.
  def build_oscal_back_matter
    BackMatterBuilder.new(self).build
  end

  private

  # Detect placeholder/sequential UUIDs that are technically valid v4
  # format but clearly not randomly generated. These patterns indicate
  # developer placeholders (e.g., a1b2c3d4-1111-4000-a000-000000000008).
  PLACEHOLDER_PATTERNS = [
    /\A(.)\1{7}-/,                          # First 8 chars all the same (00000000-, aaaaaaaa-)
    /0{6,}/,                                # 6+ consecutive zeros
    /\Aa1b2c3d4-/i,                         # Known sparc-iac placeholder prefix
    /\A12345678-/,                           # Sequential digits
    /\A(.)(.)\1\2\1\2\1\2-/                 # Repeating 2-char pattern (abababab-)
  ].freeze

  def placeholder_uuid?(uuid)
    PLACEHOLDER_PATTERNS.any? { |pattern| uuid.match?(pattern) }
  end

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
