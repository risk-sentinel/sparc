# frozen_string_literal: true

require "rails_helper"

# #1106 F2 — `control-origination` is NIST's, not ours: NIST defines it in the
# SSP model, under NIST's implicit namespace, with an ENFORCED vocabulary
# (`allow-other="no"`), allowed on the requirement, a statement and a
# by-component (`(.|statement|.//by-component)`).
#
# #1312 — each statement item records its own origination, one or more of
# NIST's values: `inherited` alone is fully inherited; `inherited` with this
# system's own is partly inherited, NIST's hybrid. The requirement carries every
# value its items carry. The control-level `control_type` (and its
# `sparc-control-origination` prop) is retired.
RSpec.describe OscalSspExportService, "control-origination conformance" do
  let(:conformance) do
    JSON.parse(Rails.root.join("lib", "oscal_conformance", "1.2.3", "conformance.json").read)
  end
  let(:nist_vocabulary) do
    conformance.dig("models", "system-security-plan", "prop_values", "control-origination")
  end

  let(:boundary) { create(:authorization_boundary) }
  let(:ssp)      { create(:ssp_document, authorization_boundary: boundary) }

  def requirement(control_id)
    JSON.parse(described_class.new(ssp.reload).export_unvalidated)
        .dig("system-security-plan", "control-implementation", "implemented-requirements")
        .find { |r| r["control-id"] == control_id }
  end

  def item!(control, statement_id, origination)
    control.ssp_control_statements.create!(statement_id: statement_id, uuid: SecureRandom.uuid,
                                           control_origination: origination)
  end

  def originations(node) = Array(node["props"]).select { _1["name"] == "control-origination" }

  it "is a NIST-defined prop with an ENFORCED vocabulary, allowed on a statement" do
    expect(nist_vocabulary["advisory"]).to be(false)
    expect(nist_vocabulary["values"]).to match_array(SspControlStatement::CONTROL_ORIGINATIONS)
    expect(nist_vocabulary["target"]).to include("statement")
  end

  it "emits each item's origination on its statement, in NIST's namespace" do
    control = ssp.ssp_controls.create!(control_id: "ac-2", title: "Account Management")
    item!(control, "ac-2_smt.a", %w[system-specific])

    statement = requirement("ac-2")["statements"].find { _1["statement-id"] == "ac-2_smt.a" }
    expect(originations(statement)).to eq([ { "name" => "control-origination", "value" => "system-specific" } ])
  end

  it "emits a partly inherited item as one prop per value" do
    control = ssp.ssp_controls.create!(control_id: "ac-2", title: "Account Management")
    item!(control, "ac-2_smt.a", %w[inherited system-specific])

    statement = requirement("ac-2")["statements"].find { _1["statement-id"] == "ac-2_smt.a" }
    expect(originations(statement).map { _1["value"] }).to eq(%w[system-specific inherited])
    expect(originations(statement).map { _1["ns"] }).to all(be_nil)
  end

  it "gives the requirement every value its items carry" do
    control = ssp.ssp_controls.create!(control_id: "pe-3", title: "Physical Access Control")
    item!(control, "pe-3_smt.a", %w[inherited])
    item!(control, "pe-3_smt.b", %w[organization])

    expect(originations(requirement("pe-3")).map { _1["value"] }).to eq(%w[organization inherited])
  end

  it "never emits a value outside NIST's enforced vocabulary" do
    control = ssp.ssp_controls.create!(control_id: "ac-2", title: "Account Management")
    SspControlStatement::CONTROL_ORIGINATIONS.each_with_index do |value, i|
      item!(control, "ac-2_smt.#{(97 + i).chr}", [ value ])
    end

    values = requirement("ac-2")["statements"].flat_map { originations(_1) }.map { _1["value"] }
    expect(values).to all(be_in(nist_vocabulary["values"]))
  end

  it "refuses a value outside the vocabulary at the model" do
    control = ssp.ssp_controls.create!(control_id: "ac-2", title: "Account Management")
    item = control.ssp_control_statements.build(statement_id: "ac-2_smt.a", uuid: SecureRandom.uuid,
                                                control_origination: [ "Hybrid — partially inherited" ])
    expect(item).not_to be_valid
  end

  it "does not export the retired control-level control type" do
    control = ssp.ssp_controls.create!(control_id: "ac-2", title: "Account Management")
    control.ssp_control_fields.create!(field_name: "control_type", field_value: "Hybrid — partially inherited")

    ir = requirement("ac-2")
    expect(Array(ir["props"]).map { _1["name"] }).not_to include("sparc-control-origination", "control-type")
  end
end
