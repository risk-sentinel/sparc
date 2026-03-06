# Builds an OSCAL v1.1.2 System Security Plan (SSP) JSON document from an
# SspDocument and its controls.  Validates the output against the official
# NIST JSON schema before returning.
#
# The SSP OSCAL model requires several structural sections beyond the raw
# control data SPARC stores.  This exporter fills required placeholders
# (system-characteristics, system-implementation, import-profile) with
# sensible defaults that pass schema validation while preserving every
# control and field value from the source document.
#
# Usage:
#   service = OscalSspExportService.new(ssp_document)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalSspExportService
  OSCAL_VERSION = "1.1.2"

  def initialize(ssp_document)
    @document = ssp_document
  end

  # Build, validate, and return pretty-printed OSCAL SSP JSON.
  def export
    data = build_ssp
    OscalSchemaValidationService.validate!(:ssp, data)
    JSON.pretty_generate(data)
  end

  # Build and return OSCAL JSON without schema validation.
  def export_unvalidated
    JSON.pretty_generate(build_ssp)
  end

  # Build the document and return the validation result (does not raise).
  def validation_result
    data = build_ssp
    OscalSchemaValidationService.validate(:ssp, data)
  end

  private

  # ── Top-level SSP envelope ─────────────────────────────────────────

  def build_ssp
    {
      "system-security-plan" => {
        "uuid"                     => SecureRandom.uuid,
        "metadata"                 => build_metadata,
        "import-profile"           => build_import_profile,
        "system-characteristics"   => build_system_characteristics,
        "system-implementation"    => build_system_implementation,
        "control-implementation"   => build_control_implementation
      }
    }
  end

  # ── Metadata ───────────────────────────────────────────────────────

  def build_metadata
    {
      "title"         => @document.name,
      "version"       => "1.0.0",
      "oscal-version" => OSCAL_VERSION,
      "last-modified" => Time.current.iso8601,
      "roles" => [
        { "id" => "prepared-by",     "title" => "Prepared By" },
        { "id" => "system-owner",    "title" => "System Owner" },
        { "id" => "authorizing-official", "title" => "Authorizing Official" }
      ],
      "parties" => [
        {
          "uuid" => SecureRandom.uuid,
          "type" => "organization",
          "name" => "SPARC Export"
        }
      ]
    }
  end

  # ── Import Profile (required — links to the control catalog baseline) ──

  def build_import_profile
    {
      "href" => "#"
    }
  end

  # ── System Characteristics ─────────────────────────────────────────

  def build_system_characteristics
    {
      "system-ids"   => [ { "id" => @document.id.to_s } ],
      "system-name"  => @document.name,
      "description"  => "System Security Plan exported from SPARC for #{@document.name}",
      "system-information" => build_system_information,
      "status" => {
        "state" => "operational"
      },
      "authorization-boundary" => {
        "description" => "Authorization boundary for #{@document.name}. Update this description to reflect the actual boundary."
      }
    }
  end

  def build_system_information
    {
      "information-types" => [
        {
          "uuid"        => SecureRandom.uuid,
          "title"       => "System Information",
          "description" => "Information processed, stored, or transmitted by #{@document.name}."
        }
      ]
    }
  end

  # ── System Implementation ──────────────────────────────────────────

  def build_system_implementation
    this_component_uuid = SecureRandom.uuid

    {
      "users" => [
        {
          "uuid"  => SecureRandom.uuid,
          "title" => "General User",
          "role-ids" => [ "system-owner" ]
        }
      ],
      "components" => [
        {
          "uuid"        => this_component_uuid,
          "type"        => "this-system",
          "title"       => @document.name,
          "description" => "The system described by this SSP.",
          "status"      => { "state" => "operational" }
        }
      ]
    }
  end

  # ── Control Implementation ─────────────────────────────────────────

  def build_control_implementation
    controls = @document.ssp_controls
                        .roots
                        .includes(:ssp_control_fields,
                                  provider_statements: :ssp_control_fields)

    {
      "description"              => "Control implementation for #{@document.name}",
      "implemented-requirements" => controls.map { |ctrl| build_implemented_requirement(ctrl) }
    }
  end

  def build_implemented_requirement(control)
    field_map = control.ssp_control_fields.index_by(&:field_name)

    result = {
      "uuid"       => SecureRandom.uuid,
      "control-id" => normalize_control_id(control.control_id)
    }

    # Props carry status, control_application, coverage_level, control_type
    props = build_props(field_map)
    result["props"] = props if props.any?

    # Statements capture implementation narrative fields
    statements = build_statements(control, field_map)
    result["statements"] = statements if statements.any?

    # Remarks aggregate free-text fields
    remarks = build_remarks(control, field_map)
    result["remarks"] = remarks if remarks.present?

    result
  end

  # ── Helpers ────────────────────────────────────────────────────────

  def normalize_control_id(raw_id)
    return "unknown" if raw_id.blank?
    # OSCAL TokenDatatype: ^(\p{L}|_)(\p{L}|\p{N}|[.\-_])*$
    # Convert parenthesised enhancements to dot notation: "AC-2 (1)" → "ac-2.1"
    raw_id.strip
          .downcase
          .gsub(/\s+/, "-")       # spaces → hyphens
          .gsub("(", ".")         # open paren → dot
          .gsub(")", "")          # strip close paren
          .gsub(/\.{2,}/, ".")    # collapse multiple dots
          .gsub(/-\./, ".")       # clean "ac-2.1" not "ac-2-.1"
  end

  def build_props(field_map)
    props = []

    status = field_map["status"]&.field_value
    props << { "name" => "implementation-status", "value" => status.downcase.gsub(/\s+/, "-") } if status.present?

    type_use = field_map["control_application"]&.field_value
    props << { "name" => "control-type", "ns" => "https://sparc.local/ns", "value" => type_use } if type_use.present?

    coverage_level = field_map["coverage_level"]&.field_value
    props << { "name" => "provided-as", "ns" => "https://sparc.local/ns", "value" => coverage_level } if coverage_level.present?

    origination = field_map["control_type"]&.field_value
    props << { "name" => "control-origination", "ns" => "https://sparc.local/ns", "value" => origination } if origination.present?

    responsible = field_map["responsible_entities"]&.field_value
    props << { "name" => "responsible-entities", "ns" => "https://sparc.local/ns", "value" => responsible } if responsible.present?

    props
  end

  def build_statements(control, field_map)
    statements = []
    control_id = normalize_control_id(control.control_id)

    # Private implementation as a statement
    priv = field_map["implementation_statement"]&.field_value
    if priv.present?
      statements << {
        "statement-id" => "#{control_id}_priv",
        "uuid"         => SecureRandom.uuid,
        "remarks"      => priv
      }
    end

    # Public implementation as a statement
    pub = field_map["implementation_summary"]&.field_value
    if pub.present?
      statements << {
        "statement-id" => "#{control_id}_pub",
        "uuid"         => SecureRandom.uuid,
        "remarks"      => pub
      }
    end

    # Provider / inherited statements
    control.provider_statements.each_with_index do |stmt, i|
      stmt_fields = stmt.ssp_control_fields.index_by(&:field_name)
      priv_impl = stmt_fields["implementation_statement"]&.field_value
      pub_impl  = stmt_fields["implementation_summary"]&.field_value
      narrative = [ priv_impl, pub_impl ].compact.join("\n\n")
      next if narrative.blank?

      statements << {
        "statement-id" => "#{control_id}_inherited_#{i + 1}",
        "uuid"         => SecureRandom.uuid,
        "remarks"      => narrative
      }
    end

    statements
  end

  def build_remarks(control, field_map)
    parts = []

    stated_req = field_map["stated_requirement"]&.field_value
    parts << "Stated Requirement: #{stated_req}" if stated_req.present?

    notes = field_map["notes"]&.field_value
    parts << "Notes: #{notes}" if notes.present?

    expected = field_map["expected_completion"]&.field_value
    parts << "Expected Completion: #{expected}" if expected.present?

    inherited_from = field_map["inherited_from"]&.field_value
    parts << "Inherited From: #{inherited_from}" if inherited_from.present?

    history = field_map["history"]&.field_value
    parts << "History: #{history}" if history.present?

    parts.join("\n\n").presence
  end
end
