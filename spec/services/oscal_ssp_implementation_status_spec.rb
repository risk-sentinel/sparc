# frozen_string_literal: true

require "rails_helper"

# `implementation-status` is NOT a prop. In OSCAL 1.2.2/1.2.3 it is a
# define-assembly with a required `state` flag, and it attaches to exactly one
# place — `by-component`.
#
# ── Why this file was rewritten ─────────────────────────────────────────────
#
# Its previous version asserted that an `implementation-status` PROP was emitted
# on `implemented-requirement` carrying a NIST-mapped value, and it passed. It
# was testing the wrong thing: an earlier pass at #1106 correctly spotted that
# `status.downcase.gsub(/\s+/, "-")` was slugifying SPARC's vocabulary into
# NIST's namespace, and fixed the VALUE — on a prop that does not exist. No value
# makes a nonexistent prop conformant.
#
# This is not a weakened test. It asserts strictly more: the old prop is ABSENT,
# the verbatim status is still preserved, and the assembly that OSCAL does define
# is emitted in the right shape and place. The generated conformance dataset
# (lib/oscal_conformance/) is used as the authority rather than a hand-copied
# list, so a NIST vocabulary change cannot leave this spec asserting stale terms.
RSpec.describe OscalSspExportService, "implementation-status conformance" do
  # NOT a constant: one declared in a describe block is defined on Object and
  # leaks into every other spec file in the suite.
  let(:conformance) do
    JSON.parse(Rails.root.join("lib", "oscal_conformance", "1.2.2", "conformance.json").read)
  end
  let(:ssp_prop_names) { conformance.dig("models", "system-security-plan", "prop_names") }

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

  it "NIST does not define implementation-status as an SSP prop at all" do
    expect(ssp_prop_names).not_to include("implementation-status"),
      "if NIST ever defines it as a prop, this spec should fail and the exporter be revisited"
  end

  # Every status SPARC offers, not a sample: the original defect was that five of
  # the eight were wrong and only the three lucky ones were ever exercised.
  [
    "Implemented", "Partially Implemented", "Planned", "Deferred",
    "Alternative Implementation", "Not Applicable",
    "Will Not Implement", "Not Implemented"
  ].each do |status|
    it "emits no implementation-status prop for #{status.inspect}, and keeps the verbatim value" do
      props = props_for(status)

      expect(props.find { |p| p["name"] == "implementation-status" }).to be_nil,
        "implementation-status is an assembly on by-component; as a prop here it claims a NIST definition that does not exist"

      sparc = props.find { |p| p["name"] == "sparc-status" }
      expect(sparc).to be_present, "the status must survive the export, in SPARC's own namespace"
      expect(sparc["ns"]).to eq(OscalNamespace.instance)
      expect(sparc["value"]).to eq(status), "the verbatim value must stay inspectable"
    end
  end

  # The other half: where OSCAL DOES define it, SPARC must emit the assembly —
  # and the vocabulary needs no mapping, because SspByComponent already stores
  # NIST's terms.
  describe "the by-component assembly, which is where OSCAL puts it" do
    it "emits state, in NIST's vocabulary, in the assembly shape" do
      component = create(:ssp_component, ssp_document: ssp, title: "App Server")
      control   = ssp.ssp_controls.create!(control_id: "ac-2", title: "Account Management")
      create(:ssp_by_component, ssp_control: control, ssp_component: component,
                                implementation_status: "partial",
                                description: "Partially implemented by the app server.")

      json = JSON.parse(described_class.new(ssp.reload).export_unvalidated)
      bc = json.dig("system-security-plan", "control-implementation", "implemented-requirements")
               .find { |r| r["control-id"] == "ac-2" }
               .fetch("by-components").first

      expect(bc["implementation-status"]).to eq("state" => "partial")
      expect(SspByComponent::IMPLEMENTATION_STATUSES).to include("partial")
    end
  end
end
