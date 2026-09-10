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
  include OscalExportReconciliation

  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  # OSCAL prop/element names reused across the export build.
  TARGET_ID            = "target-id".freeze
  # #1114 — the two `finding.target.type` values OSCAL allows. Named because
  # they are a closed vocabulary from the schema, not incidental strings.
  TARGET_TYPE_STATEMENT = "statement-id".freeze
  TARGET_TYPE_OBJECTIVE = "objective-id".freeze
  REVIEWED_CONTROLS    = "reviewed-controls".freeze
  RELATED_OBSERVATIONS = "related-observations".freeze
  OBSERVATION_UUID     = "observation-uuid".freeze

  def initialize(sar_document)
    @document = sar_document
    eager_load_associations
  end

  def export
    # #911 layer 2 — never publish a control-id that resolves to no loaded
    # catalog. TokenDatatype constrains the character set, not existence.
    refuse_unresolvable_controls!(label: "Assessment results", name: @document.name,
                                  control_ids: @document.sar_controls.pluck(:control_id))
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
      sar_findings: [ :sar_finding_observations, :sar_finding_risks, :sar_control_objective, :ssp_control_statement ],
      sar_risks: [ :sar_risk_observations ]
    ).to_a
    @components = @document.sar_local_components.to_a
    # #1114 — objectives are preloaded because the export now emits a finding per
    # determined objective; without this it is one query per control on a
    # document that routinely carries hundreds.
    @controls = @document.sar_controls.order(:row_order)
                         .includes(:sar_control_fields, :sar_control_objectives).to_a
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
        { "uuid" => OscalUuidService.org_party_uuid_for(@document),
          "type" => "organization", "name" => "SPARC Export" }
      ]
    )
  end

  # ── Import AP ────────────────────────────────────────────────────

  def build_import_ap
    # #395 P2: prefer `uuid:<sap.uuid>` from the linked SapDocument FK.
    # Fall back to the raw `import_ap_href` round-trip column when no FK
    # is set, then "#" as the schema-required last resort.
    href = OscalMetadata.import_href_for(@document.sap_document) ||
           @document.import_ap_href.presence ||
           "#"
    { "href" => href }
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
      REVIEWED_CONTROLS => result.reviewed_controls_data.presence,
      "assessment-log"    => build_assessment_log(result.assessment_log_data),
      "attestations"      => result.attestations_data.presence,
      # Explicit order: an unordered association is emitted in whatever
      # order Postgres returns, so two exports of one unchanged document
      # differ. That breaks diffing, hashing and signing of artifacts.
      "observations"      => build_observations(result.sar_observations.order(:id)),
      "risks"             => build_risks(result.sar_risks.order(:id)),
      "findings"          => build_findings(result.sar_findings.order(:id)),
      "props"             => result.props_data.presence,
      "links"             => result.links_data.presence,
      "remarks"           => result.remarks
    }.compact

    # Ensure reviewed-controls has at minimum a placeholder if not present
    entry[REVIEWED_CONTROLS] ||= {
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
        "characterizations"    => risk.characterizations_for_export,
        "mitigating-factors"   => risk.mitigating_factors_data.presence,
        "deadline"             => risk.deadline&.iso8601,
        "remediations"         => risk.remediations_data.presence,
        "risk-log"             => risk.risk_log_data.presence,
        RELATED_OBSERVATIONS => build_risk_observations(risk),
        "props"                => risk.props_data.presence,
        "links"                => risk.links_data.presence,
        "remarks"              => risk.remarks
      }.compact
    end
  end

  def build_risk_observations(risk)
    obs_records = risk.sar_risk_observations.to_a
    return nil if obs_records.empty?
    obs_records.map { |ro| { OBSERVATION_UUID => ro.sar_observation.uuid } }
  end

  # ── Findings ─────────────────────────────────────────────────────

  def build_findings(findings)
    return nil if findings.empty?
    findings.map do |finding|
      {
        "uuid"                          => finding.uuid,
        "title"                         => finding.title,
        "description"                   => finding.description,
        "target"                        => build_finding_target(finding),
        "implementation-statement-uuid" => finding.implementation_statement_uuid,
        "origins"                       => finding.origins_data.presence,
        RELATED_OBSERVATIONS          => build_finding_observations(finding),
        "related-risks"                 => build_finding_risks(finding),
        "props"                         => finding.props_data.presence,
        "links"                         => finding.links_data.presence,
        "remarks"                       => finding.remarks
      }.compact
    end
  end

  # Target precedence (most specific first):
  #   1. SspControlStatement (#393) -- type: "statement-id", id: statement_id
  #   2. SarControlObjective (#390) -- type: "objective-id", id: objective_id
  #   3. Pre-existing target_data preserved on import
  # The needs_objective_link flag is an internal marker -- never export it.
  def build_finding_target(finding)
    base = (finding.target_data || {}).except("needs_objective_link")
    if finding.ssp_control_statement_id.present? && finding.ssp_control_statement
      base["type"]      = TARGET_TYPE_STATEMENT
      base[TARGET_ID] = finding.ssp_control_statement.statement_id
    elsif finding.sar_control_objective_id.present? && finding.sar_control_objective
      base["type"]      = TARGET_TYPE_OBJECTIVE
      base[TARGET_ID] = finding.sar_control_objective.objective_id
    end
    honest_target_type(base).presence
  end

  # #1114 — a target may not CLAIM to be an objective when it is not one.
  #
  # Where neither link above resolves, the target falls through to whatever
  # `target_data` carried in from the import — and the seeded estate imports
  # `{"type" => "objective-id", "target-id" => "ac-1"}`. Measured on the demo
  # SAR: 150 findings, all 150 declaring `objective-id` against a CONTROL id.
  #
  # `objective-id` must reference an 800-53A assessment objective (`ac-1_obj.a-1`).
  # `ac-1` is a control. No validator catches the difference because both are
  # strings, so the document is schema-valid and false — a consumer resolving the
  # reference finds nothing.
  #
  # An unresolvable claim is DOWNGRADED, never dropped: `statement-id` is what a
  # control-level target actually is, and the finding itself is real. This
  # corrects the assertion without discarding the assessment.
  def honest_target_type(base)
    return base if base.blank?
    return base unless base["type"].to_s == TARGET_TYPE_OBJECTIVE

    target = base[TARGET_ID].to_s
    return base if known_objective_ids.include?(target)

    base.merge("type" => TARGET_TYPE_STATEMENT)
  end

  # Every objective id this document actually holds. One query, memoised: this
  # runs per finding, and a SAR carries hundreds.
  def known_objective_ids
    @known_objective_ids ||= SarControlObjective
                               .joins(:sar_control)
                               .where(sar_controls: { sar_document_id: @document.id })
                               .distinct.pluck(:objective_id).to_set
  end

  def build_finding_observations(finding)
    obs_records = finding.sar_finding_observations.to_a
    return nil if obs_records.empty?
    obs_records.map { |fo| { OBSERVATION_UUID => fo.sar_observation.uuid } }
  end

  def build_finding_risks(finding)
    risk_records = finding.sar_finding_risks.to_a
    return nil if risk_records.empty?
    risk_records.map { |fr| { "risk-uuid" => fr.sar_risk.uuid } }
  end

  # #1114 — the findings an assessment actually determined, one per objective.
  #
  # Only objectives with a determination are emitted. OSCAL has no "unknown"
  # state for a finding target — `status.state` is REQUIRED and the enum is
  # exactly `satisfied | not-satisfied` — so an objective still `pending` or
  # `in-progress` must produce NO finding. Emitting one would assert assurance
  # nobody established, which is the worst error an assessment artifact can make.
  # `not_applicable` is excluded for the same reason: it is a scoping decision,
  # not a determination that the objective is satisfied.
  def build_objective_findings(control, obs_uuid)
    # `determinable?` as well as `determined?`: a CONTAINER carries a label and no
    # prose, so there is nothing stated to determine about it. If one ever holds a
    # determination — imported that way, or set before the UI stopped offering it
    # — exporting a finding for it would assert a judgement about a grouping node.
    control.sar_control_objectives.select { |o| o.determinable? && o.determined? }.map do |objective|
      {
        "uuid"                 => OscalUuidService.derived(@document.uuid, "objective-finding", objective.uuid),
        "title"                => "Finding for #{objective.label.presence || objective.objective_id}",
        "description"          => objective.prose.presence ||
                                  "Determination for #{objective.objective_id}",
        "target"               => {
          "type"      => TARGET_TYPE_OBJECTIVE,
          TARGET_ID => objective.objective_id,
          "status"    => { "state" => objective.oscal_state }
        },
        RELATED_OBSERVATIONS => [ { OBSERVATION_UUID => obs_uuid } ]
      }
    end
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
      obs_uuid = OscalUuidService.derived(@document.uuid, "synthesized-observation", control.uuid)
      observations << {
        "uuid"        => obs_uuid,
        "title"       => "Assessment of #{control.control_id}",
        "description" => build_synthesized_observation_description(control, field_map),
        "methods"     => [ "TEST" ],
        "collected"   => (@document.assessment_start || @document.created_at)&.iso8601
      }.compact

      obs_uuid_map[control.id] = obs_uuid

      # #1114 — one finding per DETERMINED 800-53A objective.
      #
      # This emitted ONE finding per control, declaring
      # `"type" => "objective-id"` while passing a CONTROL id as the target. That
      # is a false statement in the artifact: `objective-id` must reference an
      # assessment objective — `ac-1_obj.a-1` — and `ac-1` is not one. The
      # schema cannot catch it, because both are just strings.
      #
      # It also flattened the assessment. NIST divides ac-1 into 24 determination
      # statements, each separately determined; a single Pass/Failed for the
      # whole control asserts more than an assessor actually found.
      objective_findings = build_objective_findings(control, obs_uuid)
      if objective_findings.any?
        findings.concat(objective_findings)
      else
        # No objective carries a determination — fall back to the control-level
        # result, and say so honestly with `type: "statement-id"`, which is what
        # a control-level target actually is.
        status_state = result_to_oscal_status(result_val)
        findings << {
          "uuid"                 => OscalUuidService.derived(@document.uuid, "synthesized-finding", control.uuid),
          "title"                => "Finding for #{control.control_id}",
          "description"          => "Assessment finding for control #{control.control_id}: #{result_val}",
          "target"               => {
            "type"      => TARGET_TYPE_STATEMENT,
            TARGET_ID => control_id,
            "status"    => { "state" => status_state }
          },
          RELATED_OBSERVATIONS => [ { OBSERVATION_UUID => obs_uuid } ]
        }
      end
    end

    {
      "uuid"               => OscalUuidService.derived(@document.uuid, "synthesized-result"),
      "title"              => "Assessment Results for #{@document.name}",
      "description"        => "Synthesized from Excel assessment data.",
      "start"              => (@document.assessment_start || @document.created_at || Time.current).iso8601,
      "end"                => (@document.assessment_end || Time.current).iso8601,
      REVIEWED_CONTROLS  => { "control-selections" => [ { "include-all" => {} } ] },
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

  # #852 — delegated to the one canonical implementation. This method used to
  # be one of four byte-identical private copies; ControlId.canonical
  # reproduces them exactly and additionally removes zero padding, so "AC-02"
  # and "ac-2" finally name the same control.
  def normalize_control_id(raw_id)
    ControlId.canonical(raw_id)
  end
end
