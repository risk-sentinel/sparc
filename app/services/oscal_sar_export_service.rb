# Builds an OSCAL v1.1.2 Assessment Results JSON document from a
# SarDocument and its relational records. Validates against the
# official NIST JSON schema before returning.
#
# Unified approach: uses enriched relational data when available,
# falling back to synthesized observations/findings from SarControl
# data for Excel-imported documents that haven't been enriched.
#
# Usage:
#   service = OscalSarExportService.new(sar_document)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalSarExportService
  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  def initialize(sar_document)
    @document = sar_document
    eager_load_associations
  end

  def export
    data = build_assessment_results
    OscalSchemaValidationService.validate!(:assessment_results, data, version: effective_oscal_version)
    JSON.pretty_generate(data)
  end

  def export_unvalidated
    JSON.pretty_generate(build_assessment_results)
  end

  def validation_result
    data = build_assessment_results
    OscalSchemaValidationService.validate(:assessment_results, data)
  end


  def effective_oscal_version
    @document.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  private

  def eager_load_associations
    @results = @document.sar_results.order(:position).includes(
      sar_observations: [ :sar_finding_observations, :sar_risk_observations ],
      sar_findings: [ :sar_finding_observations, :sar_finding_risks ],
      sar_risks: [ :sar_risk_observations ]
    ).to_a
    @components = @document.sar_local_components.to_a
    @controls = @document.sar_controls.order(:row_order).includes(:sar_control_fields).to_a
  end

  # ── Top-level Assessment Results envelope ──────────────────────────

  def build_assessment_results
    {
      "assessment-results" => {
        "uuid"              => @document.uuid,
        "metadata"          => build_metadata,
        "import-ap"         => build_import_ap,
        "local-definitions" => build_local_definitions,
        "results"           => build_results,
        "back-matter"       => build_back_matter
      }.compact
    }
  end

  # ── Metadata ─────────────────────────────────────────────────────

  def build_metadata
    @document.build_oscal_metadata(
      default_version: @document.sar_version || "1.0.0",
      default_roles: [
        { "id" => "assessor", "title" => "Security Controls Assessor" }
      ],
      default_parties: [
        { "uuid" => SecureRandom.uuid, "type" => "organization", "name" => "SPARC Export" }
      ]
    )
  end

  # ── Import AP ────────────────────────────────────────────────────

  def build_import_ap
    { "href" => @document.import_ap_href.presence || "#" }
  end

  # ── Local Definitions ────────────────────────────────────────────

  def build_local_definitions
    parts = {}

    if @components.any?
      parts["components"] = @components.map do |comp|
        {
          "uuid"              => comp.uuid,
          "type"              => comp.component_type,
          "title"             => comp.title,
          "description"       => comp.description,
          "purpose"           => comp.purpose,
          "status"            => build_component_status(comp),
          "responsible-roles" => comp.responsible_roles_data.presence,
          "protocols"         => comp.protocols_data.presence,
          "props"             => comp.props_data.presence,
          "links"             => comp.links_data.presence,
          "remarks"           => comp.remarks
        }.compact
      end
    end

    # Merge preserved local-definitions extra (activities, assessment-assets, etc.)
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

  # ── Results ──────────────────────────────────────────────────────

  def build_results
    if @results.any?
      @results.map { |result| build_result(result) }
    else
      # Fallback: synthesize a result from Excel SarControl data
      [ build_synthesized_result ]
    end
  end

  def build_result(result)
    entry = {
      "uuid"              => result.uuid,
      "title"             => result.title,
      "description"       => result.description,
      "start"             => result.start_time&.iso8601,
      "end"               => result.end_time&.iso8601,
      "reviewed-controls" => result.reviewed_controls_data.presence,
      "assessment-log"    => build_assessment_log(result.assessment_log_data),
      "attestations"      => result.attestations_data.presence,
      "observations"      => build_observations(result.sar_observations),
      "risks"             => build_risks(result.sar_risks),
      "findings"          => build_findings(result.sar_findings),
      "props"             => result.props_data.presence,
      "links"             => result.links_data.presence,
      "remarks"           => result.remarks
    }.compact

    # Ensure reviewed-controls has at minimum a placeholder if not present
    entry["reviewed-controls"] ||= {
      "control-selections" => [ { "include-all" => {} } ]
    }

    entry
  end

  def build_assessment_log(log_data)
    return nil if log_data.blank?
    if log_data.is_a?(Array)
      return nil if log_data.empty?
      { "entries" => log_data }
    else
      log_data
    end
  end

  # ── Observations ─────────────────────────────────────────────────

  def build_observations(observations)
    return nil if observations.empty?
    observations.map do |obs|
      {
        "uuid"              => obs.uuid,
        "title"             => obs.title,
        "description"       => obs.description,
        "methods"           => obs.methods_data.presence,
        "types"             => obs.types_data.presence,
        "origins"           => obs.origins_data.presence,
        "subjects"          => obs.subjects_data.presence,
        "relevant-evidence" => obs.relevant_evidence_data.presence,
        "collected"         => obs.collected&.iso8601,
        "expires"           => obs.expires&.iso8601,
        "props"             => obs.props_data.presence,
        "links"             => obs.links_data.presence,
        "remarks"           => obs.remarks
      }.compact
    end
  end

  # ── Risks ────────────────────────────────────────────────────────

  def build_risks(risks)
    return nil if risks.empty?
    risks.map do |risk|
      {
        "uuid"                 => risk.uuid,
        "title"                => risk.title,
        "description"          => risk.description,
        "statement"            => risk.statement,
        "status"               => risk.status,
        "origins"              => risk.origins_data.presence,
        "threat-ids"           => risk.threat_ids_data.presence,
        "characterizations"    => risk.characterizations_data.presence,
        "mitigating-factors"   => risk.mitigating_factors_data.presence,
        "deadline"             => risk.deadline&.iso8601,
        "remediations"         => risk.remediations_data.presence,
        "risk-log"             => risk.risk_log_data.presence,
        "related-observations" => build_risk_observations(risk),
        "props"                => risk.props_data.presence,
        "links"                => risk.links_data.presence,
        "remarks"              => risk.remarks
      }.compact
    end
  end

  def build_risk_observations(risk)
    obs_records = risk.sar_risk_observations.to_a
    return nil if obs_records.empty?
    obs_records.map { |ro| { "observation-uuid" => ro.sar_observation.uuid } }
  end

  # ── Findings ─────────────────────────────────────────────────────

  def build_findings(findings)
    return nil if findings.empty?
    findings.map do |finding|
      {
        "uuid"                          => finding.uuid,
        "title"                         => finding.title,
        "description"                   => finding.description,
        "target"                        => finding.target_data.presence,
        "implementation-statement-uuid" => finding.implementation_statement_uuid,
        "origins"                       => finding.origins_data.presence,
        "related-observations"          => build_finding_observations(finding),
        "related-risks"                 => build_finding_risks(finding),
        "props"                         => finding.props_data.presence,
        "links"                         => finding.links_data.presence,
        "remarks"                       => finding.remarks
      }.compact
    end
  end

  def build_finding_observations(finding)
    obs_records = finding.sar_finding_observations.to_a
    return nil if obs_records.empty?
    obs_records.map { |fo| { "observation-uuid" => fo.sar_observation.uuid } }
  end

  def build_finding_risks(finding)
    risk_records = finding.sar_finding_risks.to_a
    return nil if risk_records.empty?
    risk_records.map { |fr| { "risk-uuid" => fr.sar_risk.uuid } }
  end

  # ── Synthesized result (fallback for un-enriched Excel imports) ──

  def build_synthesized_result
    observations = []
    findings = []
    obs_uuid_map = {}

    @controls.each do |control|
      next if control.control_id.blank?

      field_map = control.sar_control_fields.index_by(&:field_name)
      result_val = field_map["result"]&.field_value.presence || "Not Tested"
      control_id = normalize_control_id(control.control_id)

      # Synthesize an observation per control
      obs_uuid = SecureRandom.uuid
      observations << {
        "uuid"        => obs_uuid,
        "title"       => "Assessment of #{control.control_id}",
        "description" => build_synthesized_observation_description(control, field_map),
        "methods"     => [ "TEST" ],
        "collected"   => (@document.assessment_start || @document.created_at)&.iso8601
      }.compact

      obs_uuid_map[control.id] = obs_uuid

      # Synthesize a finding per control
      status_state = result_to_oscal_status(result_val)
      findings << {
        "uuid"                 => SecureRandom.uuid,
        "title"                => "Finding for #{control.control_id}",
        "description"          => "Assessment finding for control #{control.control_id}: #{result_val}",
        "target"               => {
          "type"      => "objective-id",
          "target-id" => control_id,
          "status"    => { "state" => status_state }
        },
        "related-observations" => [ { "observation-uuid" => obs_uuid } ]
      }
    end

    {
      "uuid"               => SecureRandom.uuid,
      "title"              => "Assessment Results for #{@document.name}",
      "description"        => "Synthesized from Excel assessment data.",
      "start"              => (@document.assessment_start || @document.created_at || Time.current).iso8601,
      "end"                => (@document.assessment_end || Time.current).iso8601,
      "reviewed-controls"  => { "control-selections" => [ { "include-all" => {} } ] },
      "observations"       => observations.presence,
      "findings"           => findings.presence
    }.compact
  end

  def build_synthesized_observation_description(control, field_map)
    parts = []
    parts << "Control: #{control.control_id}"
    parts << "Result: #{field_map['result']&.field_value}" if field_map["result"]&.field_value.present?
    parts << "Notes: #{field_map['notes_weakness']&.field_value}" if field_map["notes_weakness"]&.field_value.present?
    parts << "Recommendation: #{field_map['recommended_fix']&.field_value}" if field_map["recommended_fix"]&.field_value.present?
    parts.join("\n")
  end

  def result_to_oscal_status(result_val)
    case result_val.to_s.downcase.strip
    when /\Apass/
      "satisfied"
    when /\Afail/, /not.satisfied/
      "not-satisfied"
    else
      "not-satisfied"
    end
  end

  # ── Back matter ──────────────────────────────────────────────────

  def build_back_matter
    @document.build_oscal_back_matter
  end

  # ── Helpers ──────────────────────────────────────────────────────

  def normalize_control_id(raw_id)
    return "unknown" if raw_id.blank?
    raw_id.strip
          .downcase
          .gsub(/\s+/, "-")
          .gsub("(", ".")
          .gsub(")", "")
          .gsub(/\.{2,}/, ".")
          .gsub(/-\./, ".")
  end
end
