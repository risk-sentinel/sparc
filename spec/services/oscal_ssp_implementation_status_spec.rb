# frozen_string_literal: true

require "rails_helper"

# `implementation-status` is NOT a prop. In OSCAL 1.2.2/1.2.3 it is a
# define-assembly with a required `state` flag, and it attaches to exactly one
# place — `by-component`. #1312: each statement item an SSP answers records its
# own status, so it rides that statement's this-system by-component; the
# control-level status (and its `sparc-status` prop) is retired.
#
# The generated conformance dataset (lib/oscal_conformance/) is the authority
# rather than a hand-copied list, so a NIST vocabulary change cannot leave this
# spec asserting stale terms.
RSpec.describe OscalSspExportService, "implementation-status conformance" do
  # NOT a constant: one declared in a describe block is defined on Object and
  # leaks into every other spec file in the suite.
  let(:conformance) do
    JSON.parse(Rails.root.join("lib", "oscal_conformance", "1.2.3", "conformance.json").read)
  end
  let(:ssp_prop_names) { conformance.dig("models", "system-security-plan", "prop_names") }

  let(:boundary) { create(:authorization_boundary) }
  let(:ssp)      { create(:ssp_document, authorization_boundary: boundary) }
  let!(:this_system) { create(:ssp_component, ssp_document: ssp, component_type: "this-system", title: "This System") }

  def export
    JSON.parse(described_class.new(ssp.reload).export_unvalidated)
  end

  def requirement(json, control_id)
    json.dig("system-security-plan", "control-implementation", "implemented-requirements")
        .find { |r| r["control-id"] == control_id }
  end

  it "NIST does not define implementation-status as an SSP prop at all" do
    expect(ssp_prop_names).not_to include("implementation-status"),
      "if NIST ever defines it as a prop, this spec should fail and the exporter be revisited"
  end

  # Every status an item can carry, not a sample.
  SspControlStatement::IMPLEMENTATION_STATUSES.each do |status|
    it "emits #{status.inspect} as the item's by-component implementation-status, and no prop" do
      control = ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy and Procedures")
      control.ssp_control_statements.create!(statement_id: "ac-1_smt.a", uuid: SecureRandom.uuid,
                                             implementation_status: status)

      ir = requirement(export, "ac-1")
      statement = ir["statements"].find { _1["statement-id"] == "ac-1_smt.a" }
      by_component = statement["by-components"].sole

      expect(by_component["component-uuid"]).to eq(this_system.uuid)
      expect(by_component["implementation-status"]).to eq("state" => status)
      expect(Array(ir["props"]).map { _1["name"] }).not_to include("implementation-status", "sparc-status")
      expect(Array(statement["props"]).map { _1["name"] }).not_to include("implementation-status")
    end
  end

  it "does not export the retired control-level status" do
    control = ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy and Procedures")
    control.ssp_control_fields.create!(field_name: "status", field_value: "Will Not Implement")

    expect(export.to_json).not_to include("Will Not Implement")
  end

  it "passes JSON Schema with item statuses, originations and expected completion" do
    control = ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy and Procedures")
    control.ssp_control_statements.create!(statement_id: "ac-1_smt.a", uuid: SecureRandom.uuid,
                                           implementation_prose: "Planned for Q2.",
                                           implementation_status: "planned",
                                           control_origination: %w[inherited system-specific],
                                           expected_completion: Date.new(2027, 3, 31))

    result = OscalSchemaValidationService.validate(:ssp, export, version: ssp.oscal_version.presence || "1.2.3")
    expect(result.errors).to be_empty
  end

  # The other half: a component's own by-component carries NIST's terms as
  # stored, with no mapping.
  describe "a component's by-component" do
    it "emits state, in NIST's vocabulary, in the assembly shape" do
      component = create(:ssp_component, ssp_document: ssp, title: "App Server")
      control   = ssp.ssp_controls.create!(control_id: "ac-2", title: "Account Management")
      create(:ssp_by_component, ssp_control: control, ssp_component: component,
                                implementation_status: "partial",
                                description: "Partially implemented by the app server.")

      bc = requirement(export, "ac-2").fetch("by-components").first

      expect(bc["implementation-status"]).to eq("state" => "partial")
      expect(SspByComponent::IMPLEMENTATION_STATUSES).to include("partial")
    end
  end
end
