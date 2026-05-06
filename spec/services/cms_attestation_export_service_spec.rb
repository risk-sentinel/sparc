require "rails_helper"

RSpec.describe CmsAttestationExportService do
  let(:evidence) { create(:evidence) }

  describe "#call" do
    context "when the attestation's evidence has multiple control links" do
      it "denormalizes one record per linked control_id" do
        evidence.evidence_control_links.create!(control_id: "AC-2")
        evidence.evidence_control_links.create!(control_id: "AC-3")
        attestation = create(:attestation, evidence: evidence,
                             frequency: "annually", status: "passed")

        records = described_class.new(Attestation.where(id: attestation.id)).call

        expect(records.length).to eq(2)
        expect(records.map { |r| r[:control_id] }).to contain_exactly("AC-2", "AC-3")
      end
    end

    context "when the attestation's evidence has no control links" do
      it "emits zero records" do
        attestation = create(:attestation, evidence: evidence)
        records = described_class.new(Attestation.where(id: attestation.id)).call
        expect(records).to be_empty
      end
    end

    it "maps SPARC fields to the CMS schema shape" do
      evidence.evidence_control_links.create!(control_id: "CA-7")
      attestation = create(:attestation,
                           evidence: evidence,
                           attester_name: "Jane Reviewer",
                           role: "isso",
                           statement: "All controls verified.",
                           attested_at: Time.utc(2026, 4, 1, 12, 0, 0),
                           frequency: "quarterly",
                           status: "passed")

      record = described_class.new(Attestation.where(id: attestation.id)).call.first

      expect(record).to include(
        control_id: "CA-7",
        explanation: "All controls verified.",
        frequency: "quarterly",
        status: "passed",
        updated: "2026-04-01T12:00:00Z",
        updated_by: "Jane Reviewer (ISSO)"
      )
    end

    it "defaults frequency to ad_hoc when not set" do
      evidence.evidence_control_links.create!(control_id: "CA-7")
      attestation = create(:attestation, evidence: evidence, frequency: nil)

      record = described_class.new(Attestation.where(id: attestation.id)).call.first
      expect(record[:frequency]).to eq("ad_hoc")
    end

    it "omits the role suffix from updated_by when role is blank" do
      evidence.evidence_control_links.create!(control_id: "CA-7")
      attestation = create(:attestation, evidence: evidence,
                           attester_name: "Anon", role: nil)

      record = described_class.new(Attestation.where(id: attestation.id)).call.first
      expect(record[:updated_by]).to eq("Anon")
    end

    it "iterates all attestations in the scope" do
      evidence.evidence_control_links.create!(control_id: "AC-2")
      a1 = create(:attestation, evidence: evidence, attester_name: "A")
      a2 = create(:attestation, evidence: evidence, attester_name: "B")

      records = described_class.new(Attestation.where(id: [ a1.id, a2.id ])).call
      expect(records.map { |r| r[:updated_by] }).to contain_exactly("A (Assessor)", "B (Assessor)")
    end
  end

  describe "#to_json" do
    it "serializes the records array" do
      evidence.evidence_control_links.create!(control_id: "AC-2")
      create(:attestation, evidence: evidence, frequency: "annually")

      json = described_class.new.to_json
      parsed = JSON.parse(json)
      expect(parsed).to be_an(Array)
      expect(parsed.first).to include("control_id" => "AC-2", "frequency" => "annually")
    end
  end
end
