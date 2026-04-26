# Builds the OSCAL back-matter section for a document by merging three
# resource sources:
#
#   1. Managed BackMatterResource records (user-created in SPARC)
#   2. Imported resources from import_metadata (preserved from OSCAL import)
#   3. SPARC identifier resource (persistent UUID per document)
#
# Deduplication: managed resources win over imported resources with the
# same UUID. This allows users to "take ownership" of imported resources.
#
# Usage:
#   BackMatterBuilder.new(ssp_document).build
#   # => { "resources" => [...] }
#
class BackMatterBuilder
  def initialize(document)
    @document = document
  end

  def build
    resources = authoritative_resources + managed_resources + deduplicated_imports + [ sparc_resource ]
    { "resources" => resources }
  end

  private

  # Instance-level authoritative resources (provider-published, highest priority).
  # Included in all document exports. Cannot be overridden by managed resources.
  def authoritative_resources
    @authoritative_resources ||= BackMatterResource.active.where(source: "authoritative")
                                                    .map(&:to_oscal_resource)
  end

  def authoritative_uuids
    @authoritative_uuids ||= BackMatterResource.active.where(source: "authoritative")
                                                .pluck(:uuid).to_set
  end

  def managed_resources
    doc_resources = @document.back_matter_resources.active
                             .where.not(source: "authoritative")
                             .map(&:to_oscal_resource)
    ctrl_resources = control_linked_resources.map(&:to_oscal_resource)
    # Exclude UUIDs already claimed by authoritative resources
    (doc_resources + ctrl_resources).uniq { |r| r["uuid"] }
                                    .reject { |r| authoritative_uuids.include?(r["uuid"]) }
  end

  def managed_uuids
    @managed_uuids ||= (
      authoritative_uuids.to_a +
      @document.back_matter_resources.active.pluck(:uuid) +
      control_linked_resources.pluck(:uuid)
    ).to_set
  end

  # Resources linked to controls within this document (not directly
  # attached to the document as resourceable, but referenced via
  # ControlBackMatterLink join records).
  def control_linked_resources
    @control_linked_resources ||= begin
      control_types = []

      if @document.respond_to?(:cdef_controls)
        control_types << [ "CdefControl", @document.cdef_controls.select(:id) ]
      end
      if @document.respond_to?(:ssp_controls)
        control_types << [ "SspControl", @document.ssp_controls.select(:id) ]
      end
      if @document.respond_to?(:catalog_controls)
        control_types << [ "CatalogControl", @document.catalog_controls.select(:id) ]
      end

      return BackMatterResource.none if control_types.empty?

      conditions = control_types.map do |type, ids|
        ControlBackMatterLink.where(linkable_type: type, linkable_id: ids)
      end

      resource_ids = conditions.reduce { |acc, c| acc.or(c) }&.select(:back_matter_resource_id)
      resource_ids ? BackMatterResource.active.where(id: resource_ids) : BackMatterResource.none
    end
  end

  def deduplicated_imports
    imported = @document.import_metadata&.dig("back_matter") || []
    imported.reject { |r| managed_uuids.include?(r["uuid"]) }
  end

  def sparc_resource
    @document.sparc_back_matter_resource
  end
end
