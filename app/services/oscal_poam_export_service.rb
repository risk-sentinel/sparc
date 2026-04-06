# Builds an OSCAL v1.1.2 Plan of Action and Milestones JSON document
# from a PoamDocument and its relational records. Validates against
# the official NIST JSON schema before returning.
#
# Usage:
#   service = OscalPoamExportService.new(poam_document)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalPoamExportService
  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  def initialize(poam_document)
    @document = poam_document
    eager_load_associations
  end

  def export
    data = build_poam
    OscalSchemaValidationService.validate!(:poam, data, version: effective_oscal_version)
    JSON.pretty_generate(data)
  end

  def export_unvalidated
    JSON.pretty_generate(build_poam)
  end

  def validation_result
    data = build_poam
    OscalSchemaValidationService.validate(:poam, data)
  end


  def effective_oscal_version
    @document.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  private

  def eager_load_associations
    @observations = @document.poam_observations.to_a
    @risks = @document.poam_risks.includes(
      poam_remediations: :poam_milestones,
      poam_risk_observations: :poam_observation
    ).to_a
    @findings = @document.poam_findings.includes(
      :poam_finding_observations, :poam_finding_risks
    ).to_a
    @components = @document.poam_local_components.to_a
    @items = @document.poam_items.order(:row_order).includes(
      :poam_item_risks, :poam_item_observations, :poam_item_findings
    ).to_a
  end

  def build_poam
    {
      "plan-of-action-and-milestones" => {
        "uuid"              => @document.uuid,
        "metadata"          => build_metadata,
        "import-ssp"        => @document.import_metadata&.dig("import_ssp"),
        "system-id"         => build_system_id,
        "local-definitions" => build_local_definitions,
        "observations"      => build_observations,
        "risks"             => build_risks,
        "findings"          => build_findings,
        "poam-items"        => build_poam_items,
        "back-matter"       => build_back_matter
      }.compact
    }
  end

  def build_metadata
    base = {
      "title"         => @document.name,
      "version"       => @document.poam_version || "1.0.0",
      "oscal-version" => effective_oscal_version,
      "last-modified" => Time.current.iso8601
    }

    # Merge preserved metadata fields (revisions, roles, parties, etc.)
    extra = @document.metadata_extra || {}
    base.merge(extra)
  end

  def build_system_id
    return nil if @document.system_id.blank?
    {
      "identifier-type" => "http://ietf.org/rfc/rfc4122",
      "id" => @document.system_id
    }
  end

  # ── Observations ─────────────────────────────────────────────────

  def build_observations
    return nil if @observations.empty?
    @observations.map do |obs|
      {
        "uuid"               => obs.uuid,
        "title"              => obs.title,
        "description"        => obs.description,
        "methods"            => obs.methods_data.presence,
        "types"              => obs.types_data.presence,
        "origins"            => obs.origins_data.presence,
        "subjects"           => obs.subjects_data.presence,
        "relevant-evidence"  => obs.relevant_evidence_data.presence,
        "collected"          => obs.collected&.iso8601,
        "expires"            => obs.expires&.iso8601,
        "props"              => obs.props_data.presence,
        "links"              => obs.links_data.presence,
        "remarks"            => obs.remarks
      }.compact
    end
  end

  # ── Risks ────────────────────────────────────────────────────────

  def build_risks
    return nil if @risks.empty?
    @risks.map do |risk|
      {
        "uuid"                => risk.uuid,
        "title"               => risk.title,
        "description"         => risk.description,
        "statement"           => risk.statement,
        "status"              => risk.status,
        "origins"             => risk.origins_data.presence,
        "threat-ids"          => risk.threat_ids_data.presence,
        "characterizations"   => risk.characterizations_data.presence,
        "mitigating-factors"  => risk.mitigating_factors_data.presence,
        "deadline"            => risk.deadline&.iso8601,
        "remediations"        => build_remediations(risk),
        "risk-log"            => risk.risk_log_data.presence,
        "related-observations" => build_risk_observations(risk),
        "props"               => risk.props_data.presence,
        "links"               => risk.links_data.presence,
        "remarks"             => risk.remarks
      }.compact
    end
  end

  def build_remediations(risk)
    rems = risk.poam_remediations.sort_by(&:position)
    return nil if rems.empty?

    rems.map do |rem|
      {
        "uuid"             => rem.uuid,
        "lifecycle"        => rem.lifecycle,
        "title"            => rem.title,
        "description"      => rem.description,
        "origins"          => rem.origins_data.presence,
        "required-assets"  => rem.required_assets_data.presence,
        "tasks"            => build_milestones(rem),
        "props"            => rem.props_data.presence,
        "links"            => rem.links_data.presence,
        "remarks"          => rem.remarks
      }.compact
    end
  end

  def build_milestones(remediation)
    milestones = remediation.poam_milestones.sort_by(&:position)
    return nil if milestones.empty?

    milestones.map do |ms|
      {
        "uuid"               => ms.uuid,
        "type"               => ms.milestone_type,
        "title"              => ms.title,
        "description"        => ms.description,
        "timing"             => ms.timing_data.presence,
        "props"              => ms.props_data.presence,
        "links"              => ms.links_data.presence,
        "responsible-roles"  => ms.responsible_roles_data.presence,
        "subjects"           => ms.subjects_data.presence,
        "remarks"            => ms.remarks
      }.compact
    end
  end

  def build_risk_observations(risk)
    obs_uuids = risk.poam_risk_observations.map { |ro| ro.poam_observation.uuid }
    return nil if obs_uuids.empty?
    obs_uuids.map { |uuid| { "observation-uuid" => uuid } }
  end

  # ── Findings ─────────────────────────────────────────────────────

  def build_findings
    return nil if @findings.empty?
    @findings.map do |finding|
      {
        "uuid"                          => finding.uuid,
        "title"                         => finding.title,
        "description"                   => finding.description,
        "target"                        => finding.target_data.presence,
        "implementation-statement-uuid" => finding.implementation_statement_uuid,
        "origins"                       => finding.origins_data.presence,
        "related-observations"          => finding.poam_finding_observations.map { |fo|
          { "observation-uuid" => fo.poam_observation_id ? PoamObservation.find(fo.poam_observation_id).uuid : nil }
        }.select { |o| o["observation-uuid"] }.presence,
        "related-risks"                 => finding.poam_finding_risks.map { |fr|
          { "risk-uuid" => fr.poam_risk_id ? PoamRisk.find(fr.poam_risk_id).uuid : nil }
        }.select { |r| r["risk-uuid"] }.presence,
        "props"                         => finding.props_data.presence,
        "links"                         => finding.links_data.presence,
        "remarks"                       => finding.remarks
      }.compact
    end
  end

  # ── Local definitions ────────────────────────────────────────────

  def build_local_definitions
    parts = {}

    if @components.any?
      parts["components"] = @components.map do |comp|
        {
          "uuid"               => comp.uuid,
          "type"               => comp.component_type,
          "title"              => comp.title,
          "description"        => comp.description,
          "purpose"            => comp.purpose,
          "status"             => build_component_status(comp),
          "responsible-roles"  => comp.responsible_roles_data.presence,
          "protocols"          => comp.protocols_data.presence,
          "props"              => comp.props_data.presence,
          "links"              => comp.links_data.presence,
          "remarks"            => comp.remarks
        }.compact
      end
    end

    # Merge preserved local-definitions extra (inventory-items, assessment-assets, etc.)
    extra = @document.local_definitions_extra || {}
    parts.merge!(extra) if extra.present?

    parts.presence
  end

  def build_component_status(comp)
    return nil if comp.status_state.blank?
    {
      "state"   => comp.status_state,
      "remarks" => comp.status_remarks
    }.compact
  end

  # ── POA&M Items ──────────────────────────────────────────────────

  def build_poam_items
    @items.map do |item|
      entry = {
        "uuid"        => item.poam_item_uuid || SecureRandom.uuid,
        "title"       => item.title,
        "description" => item.description,
        "origins"     => item.origins_data.presence,
        "props"       => item.props_data.presence,
        "links"       => item.links_data.presence,
        "remarks"     => item.remarks
      }

      # Related observations (from join table)
      obs_uuids = item.poam_item_observations.map { |io| io.poam_observation_id }
      if obs_uuids.any?
        obs_records = @observations.select { |o| obs_uuids.include?(o.id) }
        entry["related-observations"] = obs_records.map { |o| { "observation-uuid" => o.uuid } }
      end

      # Related risks (from join table)
      risk_ids = item.poam_item_risks.map { |ir| ir.poam_risk_id }
      if risk_ids.any?
        risk_records = @risks.select { |r| risk_ids.include?(r.id) }
        entry["related-risks"] = risk_records.map { |r| { "risk-uuid" => r.uuid } }
      end

      # Related findings (from join table)
      finding_ids = item.poam_item_findings.map { |if_rec| if_rec.poam_finding_id }
      if finding_ids.any?
        finding_records = @findings.select { |f| finding_ids.include?(f.id) }
        entry["related-findings"] = finding_records.map { |f| { "finding-uuid" => f.uuid } }
      end

      entry.compact
    end
  end

  # ── Back matter ──────────────────────────────────────────────────

  def build_back_matter
    @document.build_oscal_back_matter
  end
end
