# Builds an OSCAL v1.1.2 Assessment Plan (SAP) JSON document from a
# SapDocument and its controls.  Validates the output against the official
# NIST JSON schema before returning.
#
# The OSCAL assessment-plan model requires structural sections including
# metadata, import-ssp, reviewed-controls, and assessment-subjects.
# This exporter populates these from the SAP document's controls and
# linked SSP/Profile references.
#
# Usage:
#   service = OscalAssessmentPlanExportService.new(sap_document)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalAssessmentPlanExportService
  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  def initialize(sap_document)
    @document = sap_document
  end

  def export
    data = build_assessment_plan
    OscalSchemaValidationService.validate!(:assessment_plan, data, version: effective_oscal_version)
    JSON.pretty_generate(data)
  end

  def export_unvalidated
    JSON.pretty_generate(build_assessment_plan)
  end

  def validation_result
    data = build_assessment_plan
    OscalSchemaValidationService.validate(:assessment_plan, data)
  end


  def effective_oscal_version
    @document.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  private

  def build_assessment_plan
    {
      "assessment-plan" => {
        "uuid"                => @document.uuid,
        "metadata"            => build_metadata,
        "import-ssp"          => build_import_ssp,
        "local-definitions"   => build_local_definitions,
        "terms-and-conditions" => build_terms_and_conditions,
        "reviewed-controls"   => build_reviewed_controls,
        "assessment-subjects" => build_assessment_subjects,
        "assessment-assets"   => build_assessment_assets,
        "back-matter"         => build_back_matter
      }.compact
    }
  end

  # ── Metadata ───────────────────────────────────────────────────────

  def build_metadata
    meta = @document.build_oscal_metadata(
      default_version: @document.sap_version || "1.0.0",
      default_roles: build_roles,
      default_parties: build_parties
    )
    append_assessment_type_prop(meta)
    meta
  end

  def append_assessment_type_prop(meta)
    return unless @document.assessment_type.present?

    meta["props"] ||= []
    unless meta["props"].any? { |p| p["name"] == "assessment-type" }
      meta["props"] << { "name" => "assessment-type", "ns" => "https://sparc.local/ns", "value" => @document.assessment_type }
    end
  end

  def build_roles
    roles = [
      { "id" => "assessor",       "title" => "Assessor" },
      { "id" => "assessment-lead", "title" => "Assessment Lead" },
      { "id" => "system-owner",   "title" => "System Owner" },
      { "id" => "csp-operations", "title" => "CSP Operations" }
    ]

    assessor_names = @document.sap_controls.where.not(assessor_name: [ nil, "" ])
                              .distinct.pluck(:assessor_name)
    assessor_names.each do |name|
      roles << { "id" => "assessor-#{name.parameterize}", "title" => name }
    end

    roles
  end

  def build_parties
    parties = [
      {
        "uuid" => OscalUuidService.org_party_uuid_for(@document),
        "type" => "organization",
        "name" => "Assessment Organization (SPARC Export)"
      }
    ]

    assessor_names = @document.sap_controls.where.not(assessor_name: [ nil, "" ])
                              .distinct.pluck(:assessor_name)
    assessor_names.each do |name|
      parties << {
        "uuid" => OscalUuidService.derived(@document.uuid, "sap-assessor-party", name),
        "type" => "person",
        "name" => name
      }
    end

    parties
  end

  # ── Import SSP ─────────────────────────────────────────────────────

  def build_import_ssp
    # #395 P2: emit `uuid:<sibling.uuid>` so a re-imported document can
    # round-trip back to the same SspDocument. Falls back to "#" only
    # when the SSP isn't linked (NIST schema requires the field).
    href = OscalMetadata.import_href_for(@document.ssp_document) || "#"
    { "href" => href }
  end

  # ── Local Definitions ──────────────────────────────────────────────

  def build_local_definitions
    # Bucket controls by individual method. Multi-method controls
    # (assessment_method like "examine,interview") appear in each
    # method's bucket so the OSCAL output reflects all methods.
    method_buckets = Hash.new { |h, k| h[k] = [] }
    @document.sap_controls
             .includes(:sap_control_objectives)
             .where.not(assessment_method: [ nil, "" ]).each do |ctrl|
      ctrl.assessment_methods.each { |m| method_buckets[m] << ctrl }
    end

    activities = method_buckets.map do |method, controls_for_method|
      {
        "uuid"        => OscalUuidService.derived(@document.uuid, "sap-activity", method),
        "title"       => "#{method.titleize} Assessment Activities",
        "description" => "Assessment activities using the #{method} method.",
        "props" => [
          { "name" => "method", "value" => method.upcase }
        ],
        "steps" => controls_for_method.map do |ctrl|
          step = {
            "uuid"        => OscalUuidService.derived(@document.uuid, "sap-step", method, ctrl.uuid),
            "title"       => "Assess #{ctrl.control_id}",
            "description" => ctrl.aggregate_objective_text.presence ||
                             "Assess #{ctrl.control_id} using #{method} method."
          }
          if ctrl.test_case.present?
            step["remarks"] = ctrl.test_case
          end
          step
        end,
        "related-controls" => {
          "control-selections" => [
            {
              "include-controls" => controls_for_method.map { |ctrl| build_include_control(ctrl) }
            }
          ]
        }
      }
    end

    return nil if activities.empty?
    { "activities" => activities }
  end

  # Builds an OSCAL include-controls[] entry. When the SapControl has
  # discrete objective records, emits statement-ids so consumers can scope
  # the assessment to specific objectives rather than the whole control.
  # Objective IDs are passed through as-is (they already use the OSCAL
  # canonical form like "ac-1_obj.a-1"); normalize_control_id is lossy and
  # would corrupt them.
  def build_include_control(ctrl)
    entry = { "control-id" => normalize_control_id(ctrl.control_id) }
    objective_ids = ctrl.sap_control_objectives.order(:row_order).pluck(:objective_id)
    entry["statement-ids"] = objective_ids if objective_ids.any?
    entry
  end

  # ── Terms and Conditions ───────────────────────────────────────────

  def build_terms_and_conditions
    parts = []

    if @document.assessment_start.present? || @document.assessment_end.present?
      schedule_text = ""
      schedule_text += "Start: #{@document.assessment_start}" if @document.assessment_start.present?
      schedule_text += " | End: #{@document.assessment_end}" if @document.assessment_end.present?

      parts << {
        "name" => "assessment-schedule",
        "title" => "Assessment Schedule",
        "prose" => schedule_text
      }
    end

    if @document.description.present?
      parts << {
        "name" => "assessment-scope",
        "title" => "Assessment Scope",
        "prose" => @document.description
      }
    end

    return nil if parts.empty?
    { "parts" => parts }
  end

  # ── Reviewed Controls ──────────────────────────────────────────────

  def build_reviewed_controls
    controls = @document.sap_controls.order(:row_order)

    control_selections = [ {
      "include-controls" => controls.map do |ctrl|
        entry = { "control-id" => normalize_control_id(ctrl.control_id) }
        if ctrl.objective.present?
          entry["statement-ids"] = [ "#{normalize_control_id(ctrl.control_id)}_obj" ]
        end
        entry
      end
    } ]

    {
      "control-selections" => control_selections
    }
  end

  # ── Assessment Subjects ────────────────────────────────────────────

  def build_assessment_subjects
    [
      {
        "type"        => "component",
        "description" => "System components included in this assessment.",
        "include-all" => {}
      }
    ]
  end

  # ── Assessment Assets ──────────────────────────────────────────────

  def build_assessment_assets
    assessment_platforms = [
      {
        "uuid"  => OscalUuidService.derived(@document.uuid, "sap-assessment-platform"),
        "title" => "Assessment Platform",
        "props" => [
          { "name" => "type", "ns" => "https://sparc.local/ns", "value" => "manual" }
        ]
      }
    ]

    {
      "assessment-platforms" => assessment_platforms
    }
  end

  # ── Helpers ────────────────────────────────────────────────────────

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

  def build_back_matter
    @document.build_oscal_back_matter
  end
end
