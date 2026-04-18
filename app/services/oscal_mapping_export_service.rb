# frozen_string_literal: true

# Builds an OSCAL v1.2.1 Mapping Collection JSON document from a ControlMapping
# and its entries.  Validates the output against the OSCAL mapping JSON schema.
#
# Usage:
#   service = OscalMappingExportService.new(control_mapping)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalMappingExportService
  DEFAULT_OSCAL_VERSION = "1.2.1"
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  def initialize(control_mapping)
    @mapping = control_mapping
    @entries = control_mapping.control_mapping_entries.to_a
  end

  def effective_oscal_version
    @mapping.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  def export
    data = build_mapping_collection
    OscalSchemaValidationService.validate!(:mapping, data, version: effective_oscal_version)
    JSON.pretty_generate(data)
  end

  def export_unvalidated
    JSON.pretty_generate(build_mapping_collection)
  end

  def validation_result
    data = build_mapping_collection
    OscalSchemaValidationService.validate(:mapping, data)
  end

  private

  def build_mapping_collection
    {
      "mapping-collection" => {
        "uuid"       => @mapping.uuid,
        "metadata"   => build_metadata,
        "provenance" => build_provenance,
        "mappings"   => build_mappings,
        "back-matter" => build_back_matter
      }.compact
    }
  end

  def build_metadata
    @mapping.build_oscal_metadata(
      default_version: @mapping.mapping_version || "1.0.0",
      default_roles: [
        { "id" => "creator", "title" => "Document Creator" }
      ],
      default_parties: [
        { "uuid" => OscalUuidService.derived(@mapping.id.to_s, "mapping-default-party"),
          "type" => "organization", "name" => "SPARC Export" }
      ]
    )
  end

  def build_provenance
    prov = {
      "method"              => @mapping.method_type,
      "matching-rationale"  => @mapping.matching_rationale,
      "status"              => @mapping.status,
      "mapping-description" => @mapping.description.presence || "Control mapping between #{@mapping.source_catalog.name} and #{@mapping.target_catalog.name}."
    }
    prov.compact
  end

  def build_mappings
    source_uuid = source_resource_uuid
    target_uuid = target_resource_uuid

    [ {
      "uuid"            => OscalUuidService.derived(@mapping.id.to_s, "mapping-set"),
      "source-resource" => { "type" => "catalog", "href" => "##{source_uuid}" },
      "target-resource" => { "type" => "catalog", "href" => "##{target_uuid}" },
      "maps"            => build_maps
    }.compact ]
  end

  def build_maps
    @entries.map do |entry|
      map = {
        "uuid"         => entry.uuid,
        "relationship" => entry.relationship,
        "sources"      => [ { "type" => entry.source_type, "id-ref" => normalize_control_id(entry.source_control_id) } ],
        "targets"      => [ { "type" => entry.target_type, "id-ref" => normalize_control_id(entry.target_control_id) } ]
      }
      map["remarks"]            = entry.remarks if entry.remarks.present?
      map["matching-rationale"] = entry.matching_rationale if entry.matching_rationale.present?
      map
    end
  end

  def build_back_matter
    {
      "resources" => [
        {
          "uuid"  => source_resource_uuid,
          "title" => @mapping.source_catalog.name,
          "props" => [ { "name" => "type", "value" => "catalog" } ]
        },
        {
          "uuid"  => target_resource_uuid,
          "title" => @mapping.target_catalog.name,
          "props" => [ { "name" => "type", "value" => "catalog" } ]
        }
      ]
    }
  end

  def source_resource_uuid
    @source_resource_uuid ||= OscalUuidService.derived(@mapping.id.to_s, "mapping-source-resource")
  end

  def target_resource_uuid
    @target_resource_uuid ||= OscalUuidService.derived(@mapping.id.to_s, "mapping-target-resource")
  end

  def normalize_control_id(id)
    id.downcase.tr(" ", "-")
  end
end
