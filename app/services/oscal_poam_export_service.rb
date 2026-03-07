# Builds an OSCAL v1.1.2 Plan of Action and Milestones JSON document
# from a PoamDocument and its items. Validates against the official NIST
# JSON schema before returning.
#
# Usage:
#   service = OscalPoamExportService.new(poam_document)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalPoamExportService
  OSCAL_VERSION = "1.1.2"

  def initialize(poam_document)
    @document = poam_document
  end

  def export
    data = build_poam
    OscalSchemaValidationService.validate!(:poam, data)
    JSON.pretty_generate(data)
  end

  def export_unvalidated
    JSON.pretty_generate(build_poam)
  end

  def validation_result
    data = build_poam
    OscalSchemaValidationService.validate(:poam, data)
  end

  private

  def build_poam
    {
      "plan-of-action-and-milestones" => {
        "uuid"         => @document.import_metadata&.dig("uuid") || SecureRandom.uuid,
        "metadata"     => build_metadata,
        "import-ssp"   => @document.import_metadata&.dig("import_ssp"),
        "system-id"    => build_system_id,
        "observations" => rebuild_observations,
        "risks"        => rebuild_risks,
        "poam-items"   => build_poam_items,
        "back-matter"  => build_back_matter
      }.compact
    }
  end

  def build_metadata
    {
      "title"         => @document.name,
      "version"       => @document.poam_version || "1.0.0",
      "oscal-version" => OSCAL_VERSION,
      "last-modified" => Time.current.iso8601
    }
  end

  def build_system_id
    return nil if @document.system_id.blank?
    {
      "identifier-type" => "http://ietf.org/rfc/rfc4122",
      "id" => @document.system_id
    }
  end

  def rebuild_observations
    obs = @document.observations_data
    return nil if obs.blank?
    obs
  end

  def rebuild_risks
    risks = @document.risks_data
    return nil if risks.blank?

    # Update risk statuses from current PoamItem data
    items = @document.poam_items.to_a
    item_by_risk = items.each_with_object({}) do |item, map|
      map[item.related_risk_uuid] = item if item.related_risk_uuid.present?
    end

    risks.map do |risk|
      updated = risk.dup
      item = item_by_risk[risk["uuid"]]
      updated["status"] = item.risk_status if item&.risk_status.present?
      updated
    end
  end

  def build_poam_items
    @document.poam_items.order(:row_order).includes(:poam_item_fields).map do |item|
      entry = {
        "uuid"        => item.poam_item_uuid || SecureRandom.uuid,
        "title"       => item.title,
        "description" => item.description
      }

      if item.related_observation_uuid.present?
        entry["related-observations"] = [ { "observation-uuid" => item.related_observation_uuid } ]
      end

      if item.related_risk_uuid.present?
        entry["related-risks"] = [ { "risk-uuid" => item.related_risk_uuid } ]
      end

      entry.compact
    end
  end

  def build_back_matter
    resources = @document.import_metadata&.dig("back_matter")
    return nil if resources.blank?
    { "resources" => resources }
  end
end
