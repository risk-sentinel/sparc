# frozen_string_literal: true

require "rails_helper"

# `implementation-status` is emitted WITHOUT an `ns`, which places it in the
# OSCAL namespace — so its value must be one of NIST's:
#
#   implemented / partial / planned / alternative / not-applicable
#
# The export built it as `status.downcase.gsub(/\s+/, "-")`, slugifying SPARC's
# own vocabulary into NIST's namespace. Three of the eight SPARC statuses
# collide with a NIST term and were right by accident; five were not, and
# `deferred` was shipping in the seeded demo SSP.
#
# NOTHING CAUGHT IT, and the reason matters: prop VALUES are Metaschema
# constraints, not JSON Schema ones. `OscalSchemaValidationService` checks JSON
# Schema, so the document validated cleanly while telling a conforming reader a
# word it cannot interpret. A schema pass is not a conformance pass.
RSpec.describe OscalSspExportService, "implementation-status conformance" do
  # NOT a constant: one declared in a describe block is defined on Object and
  # leaks into every other spec file in the suite.
  let(:nist_allowed) { %w[implemented partial planned alternative not-applicable] }

  let(:boundary) { create(:authorization_boundary) }
  let(:ssp)      { create(:ssp_document, authorization_boundary: boundary) }

  def props_for(status)
    control = ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy and Procedures")
    control.ssp_control_fields.create!(field_name: "status", field_value: status)
    json = JSON.parse(described_class.new(ssp.reload).export_unvalidated)
    ir = json.dig("system-security-plan", "control-implementation", "implemented-requirements")
             .find { |r| r["control-id"] == "ac-1" }
    ir["props"] || []
  end

  # Every status SPARC offers, not a sample: the defect was that five of the
  # eight were wrong and only the three lucky ones were ever exercised.
  {
    "Implemented"                => "implemented",
    "Partially Implemented"      => "partial",
    "Planned"                    => "planned",
    "Deferred"                   => "planned",
    "Alternative Implementation" => "alternative",
    "Not Applicable"             => "not-applicable"
  }.each do |sparc_status, nist_value|
    it "maps #{sparc_status.inspect} to the NIST term #{nist_value.inspect}" do
      oscal = props_for(sparc_status).find { |p| p["name"] == "implementation-status" }

      expect(oscal).to be_present, "#{sparc_status} has a NIST equivalent and must emit the OSCAL prop"
      expect(oscal["ns"]).to be_nil, "implementation-status belongs to the OSCAL namespace"
      expect(oscal["value"]).to eq(nist_value)
      expect(nist_allowed).to include(oscal["value"])
    end
  end

  # The other direction. NIST cannot express these, and inventing a term inside
  # its namespace would be worse than saying nothing there.
  [ "Will Not Implement", "Not Implemented" ].each do |sparc_only|
    it "does NOT invent a NIST term for #{sparc_only.inspect}" do
      props = props_for(sparc_only)

      expect(props.find { |p| p["name"] == "implementation-status" }).to be_nil,
        "#{sparc_only} has no NIST equivalent; emitting one would misinform a conforming reader"
      sparc = props.find { |p| p["name"] == "sparc-status" }
      expect(sparc).to be_present
      expect(sparc["ns"]).to eq(described_class::SPARC_NS)
      expect(sparc["value"]).to eq(sparc_only)
    end
  end

  it "always preserves the verbatim SPARC status alongside the mapped one" do
    props = props_for("Deferred")

    expect(props.find { |p| p["name"] == "implementation-status" }["value"]).to eq("planned")
    expect(props.find { |p| p["name"] == "sparc-status" }["value"]).to eq("Deferred"),
      "the mapping must stay inspectable — a reader has to be able to see what SPARC actually recorded"
  end
end
