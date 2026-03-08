require "rails_helper"

RSpec.describe Evidence, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:evidence_type) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:project).optional }
    it { is_expected.to have_many(:evidence_control_links).dependent(:destroy) }
    it { is_expected.to have_many(:attestations).dependent(:destroy) }
  end

  describe "enums" do
    it "defines evidence_type enum with all types" do
      expect(Evidence.evidence_types.keys).to contain_exactly(
        "artifact", "screenshot", "log", "config_export",
        "scan_result", "signed_statement", "policy_document", "test_result"
      )
    end

    it "defines status enum with all statuses" do
      expect(Evidence.statuses.keys).to contain_exactly(
        "draft", "collected", "reviewed", "attested", "expired"
      )
    end
  end

  describe "#type_label" do
    it "returns human-readable label for evidence type" do
      evidence = build(:evidence, evidence_type: "scan_result")
      expect(evidence.type_label).to eq("Scan Result")
    end
  end

  describe "#status_label" do
    it "returns human-readable label for status" do
      evidence = build(:evidence, status: "collected")
      expect(evidence.status_label).to eq("Collected")
    end
  end

  describe "#linked_control_ids" do
    it "returns unique control IDs from links" do
      evidence = create(:evidence)
      create(:evidence_control_link, evidence: evidence, control_id: "AC-01")
      create(:evidence_control_link, evidence: evidence, control_id: "AC-02")

      expect(evidence.linked_control_ids).to contain_exactly("AC-01", "AC-02")
    end
  end

  describe "#attested?" do
    it "returns false when no attestations exist" do
      evidence = create(:evidence)
      expect(evidence.attested?).to be false
    end

    it "returns true when attestations exist" do
      evidence = create(:evidence)
      create(:attestation, evidence: evidence)
      expect(evidence.attested?).to be true
    end
  end
end
