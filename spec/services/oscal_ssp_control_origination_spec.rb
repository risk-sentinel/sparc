# frozen_string_literal: true

require "rails_helper"

# #1106 F2 — `control-origination` is NIST's, not ours.
#
# The issue recorded it as a FedRAMP prop name borrowed under a SPARC namespace,
# and proposed either mapping to FedRAMP's vocabulary under FedRAMP's ns, or
# renaming. That premise is wrong for OSCAL 1.2.2/1.2.3: NIST defines
# `control-origination` in the SSP model itself. SPARC was emitting the right
# NAME under the wrong NAMESPACE with the wrong VALUES.
#
# The vocabulary is ENFORCED (`allow-other="no"` in the metaschema), so a value
# outside it is a hard conformance violation, not a style preference. The allowed
# list is read from the generated dataset rather than hand-copied, so a NIST
# change cannot leave this spec asserting stale terms.
RSpec.describe OscalSspExportService, "control-origination conformance" do
  let(:conformance) do
    JSON.parse(Rails.root.join("lib", "oscal_conformance", "1.2.2", "conformance.json").read)
  end
  let(:nist_vocabulary) do
    conformance.dig("models", "system-security-plan", "prop_values", "control-origination")
  end

  let(:boundary) { create(:authorization_boundary) }
  let(:ssp)      { create(:ssp_document, authorization_boundary: boundary) }

  # The control id is parameterised because one example exercises several
  # values, and SspControl enforces uniqueness per document.
  def props_for(origination, control_id: "ac-1")
    control = ssp.ssp_controls.create!(control_id: control_id, title: "Policy and Procedures")
    control.ssp_control_fields.create!(field_name: "control_type", field_value: origination)
    json = JSON.parse(described_class.new(ssp.reload).export_unvalidated)
    json.dig("system-security-plan", "control-implementation", "implemented-requirements")
        .find { |r| r["control-id"] == control_id }["props"] || []
  end

  it "is a NIST-defined prop with an ENFORCED vocabulary" do
    expect(nist_vocabulary).to be_present
    expect(nist_vocabulary["advisory"]).to be(false),
      "if NIST relaxes this to allow-other, the mapping below stops being mandatory"
    expect(nist_vocabulary["values"]).to contain_exactly(
      "organization", "system-specific", "customer-configured", "customer-provided", "inherited"
    )
  end

  {
    "System Specific" => "system-specific",
    "Inherited from provider" => "inherited"
  }.each do |sparc_value, nist_value|
    it "maps #{sparc_value.inspect} to NIST's #{nist_value.inspect}, in NIST's namespace" do
      prop = props_for(sparc_value).find { |p| p["name"] == "control-origination" }

      expect(prop).to be_present
      expect(prop["ns"]).to be_nil,
        "control-origination belongs to NIST, and NIST's namespace is implicit — an explicit SPARC ns made it OURS"
      expect(prop["value"]).to eq(nist_value)
      expect(nist_vocabulary["values"]).to include(prop["value"])
    end
  end

  # The other direction, and the rule that keeps this honest: when NIST cannot
  # express the value, say nothing in NIST's namespace rather than inventing a
  # term there.
  [ "Hybrid — partially inherited", "Not Applicable" ].each do |unmappable|
    it "does NOT invent a NIST term for #{unmappable.inspect}" do
      props = props_for(unmappable)

      expect(props.find { |p| p["name"] == "control-origination" }).to be_nil,
        "OSCAL expresses split responsibility per-component; inventing a control-level term would misinform a reader"
    end
  end

  it "always preserves the verbatim SPARC value under the deployment namespace" do
    props = props_for("Hybrid — partially inherited")
    sparc = props.find { |p| p["name"] == "sparc-control-origination" }

    expect(sparc).to be_present, "an unmappable value must still survive the export"
    expect(sparc["ns"]).to eq(OscalNamespace.instance)
    expect(sparc["value"]).to eq("Hybrid — partially inherited")
  end

  it "never emits a SPARC value inside NIST's vocabulary" do
    described_class::NIST_CONTROL_ORIGINATION.each_key.with_index do |sparc_value, i|
      prop = props_for(sparc_value.titleize, control_id: "ac-#{i + 1}")
               .find { |p| p["name"] == "control-origination" }
      next if prop.nil?

      expect(nist_vocabulary["values"]).to include(prop["value"]),
        "#{prop['value'].inspect} is not in NIST's enforced vocabulary"
    end
  end
end
