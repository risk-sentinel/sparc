# frozen_string_literal: true

# Shared assertions for the #817 end-to-end OSCAL pipeline proof.
#
# #817 requires every document the pipeline produces to be exported AND
# schema-validated in JSON, YAML and XML. That is the same three-way assertion
# at every stage, so it lives here rather than being retyped (and subtly varied)
# in each one.
#
# The three serializations are NOT three independent checks of the same thing.
# JSON and YAML share a data model, so YAML validation catches serialization
# damage — a mangled timestamp, a coerced numeric, a lost empty array. XML is a
# genuinely different model with its own NIST XSD, element ordering rules and
# attribute-versus-element distinctions, and it is where OSCAL exports break
# most often (see the control-catalog `<select>` collision fixed in #816).
module OscalSerializationMatrix
  # Assert `json` is schema-valid, then that it survives conversion to YAML and
  # XML still schema-valid. Returns { json:, yaml:, xml: } so a caller can make
  # further content assertions without re-exporting.
  #
  # `label` names the pipeline stage in failure output — with a dozen documents
  # flowing through, "profile invalid" is not enough to act on.
  def expect_valid_in_all_serializations(json, model_type:, label:)
    aggregate_failures("#{label} — all three serializations") do
      expect_valid_json_and_yaml(json, model_type: model_type, label: label)
      expect_valid_xml(json, model_type: model_type, label: label)
    end
  end

  # JSON and YAML share a data model, so this pair catches serialization damage
  # (mangled timestamps, coerced numerics, lost empty arrays).
  def expect_valid_json_and_yaml(json, model_type:, label:)
    json_result = OscalSchemaValidationService.validate_json(model_type, json)
    expect(json_result.valid?).to be(true),
      -> { "#{label}: JSON failed #{model_type} schema — #{format_errors(json_result)}" }

    yaml = OscalExportFormatService.to_yaml(json)
    yaml_data = YAML.safe_load(yaml, permitted_classes: [ Date, Time, DateTime ], aliases: true)
    yaml_result = OscalSchemaValidationService.validate(model_type, yaml_data)
    expect(yaml_result.valid?).to be(true),
      -> { "#{label}: YAML failed #{model_type} schema — #{format_errors(yaml_result)}" }

    { json: json, yaml: yaml }
  end

  # XML is a genuinely different model with its own NIST XSD, element ordering
  # rules and attribute-versus-element distinctions. It is separated from the
  # JSON/YAML pair so a spec can mark it pending against a known converter
  # defect without also giving up the JSON and YAML coverage.
  def expect_valid_xml(json, model_type:, label:)
    xml = OscalExportFormatService.to_xml(json, model_type)
    xml_result = OscalSchemaValidationService.validate_xml(model_type, xml)
    expect(xml_result.valid?).to be(true),
      -> { "#{label}: XML failed the #{model_type} XSD — #{format_errors(xml_result)}" }

    xml
  end

  # The negative direction. `mutate` receives the parsed export and damages it;
  # the result must be REJECTED. Without this, a validator that always returned
  # true would satisfy every positive assertion above.
  def expect_rejected_by_schema(json, model_type:, label:)
    data = JSON.parse(json)
    yield(data)

    result = OscalSchemaValidationService.validate(model_type, data)
    expect(result.valid?).to be(false),
      -> { "#{label}: schema ACCEPTED a document it should have rejected" }
    result
  end

  private

  # Schema errors arrive as long arrays; the first few identify the fault and
  # the rest bury it.
  def format_errors(result)
    errors = Array(result.errors)
    return "(no error detail)" if errors.empty?

    shown = errors.first(5).join("; ")
    errors.size > 5 ? "#{shown} (+#{errors.size - 5} more)" : shown
  end
end

RSpec.configure do |config|
  config.include OscalSerializationMatrix, :oscal_pipeline
end
