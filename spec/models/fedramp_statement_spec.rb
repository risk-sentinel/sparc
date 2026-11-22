# frozen_string_literal: true

require "rails_helper"

# #1390 — a boundary's answer to a FedRAMP rule or KSI.
RSpec.describe FedrampStatement do
  let(:boundary) { create(:authorization_boundary, :fedramp) }

  def build_statement(**attrs)
    described_class.new({ authorization_boundary: boundary, kind: "frr", rule_id: "SDR-CSO-FRR" }.merge(attrs))
  end

  it "takes its statuses and evidence types from the SDR schema" do
    expect(described_class.statuses).to eq([ "Implemented", "Not Implemented", "Partially Implemented" ])
    expect(described_class.evidence_types).to include("Log", "Policy", "Audit Record")
  end

  it "refuses a status, kind or rule id it does not know" do
    s = build_statement(status: "Done", kind: "xyz", rule_id: "nope")
    expect(s).not_to be_valid
    expect(s.errors.attribute_names).to include(:status, :kind, :rule_id)
  end

  it "keeps one statement per boundary, kind and rule" do
    build_statement(status: "Implemented").save!
    expect(build_statement).not_to be_valid
  end

  it "trims text, drops blank tests and empty evidence rows" do
    s = build_statement(kind: "ksi", rule_id: "KSI-CED-RAT", implementation: "  done  ", tests: [ " t1 ", "" ],
                        evidence: { "0" => { "evidence_type" => "Log", "description" => " d " }, "1" => { "description" => "" } })
    expect(s.implementation).to eq("done")
    expect(s.tests).to eq([ "t1" ])
    expect(s.evidence).to eq([ { "evidence_type" => "Log", "description" => "d" } ])
  end

  it "checks each evidence entry's type, location and date" do
    s = build_statement(evidence: [ { evidence_type: "Video", location: "ftp://x", last_updated: "yesterday" } ])
    expect(s).not_to be_valid
    expect(s.errors.full_messages.join).to include("type must be one of", "location must be an http(s) address",
                                                   "last updated must be a date")
  end

  it "counts up the boundary's SDR version on each change, and not on a save that changes nothing" do
    s = build_statement(status: "Implemented")
    expect { s.save! }.to change { boundary.reload.fedramp_sdr_version }.by(1)
    expect { s.update!(implementation: "How.") }.to change { boundary.reload.fedramp_sdr_version }.by(1)
    expect { s.update!(implementation: "How.") }.not_to(change { boundary.reload.fedramp_sdr_version })
    expect { s.destroy! }.to change { boundary.reload.fedramp_sdr_version }.by(1)
  end
end
