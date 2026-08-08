require "rails_helper"

RSpec.describe Evidence, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:evidence_type) }
    it { is_expected.to validate_presence_of(:status) }
  end

  # #903 / NIST AU-10 — evidence cannot have been collected in the future.
  # Both write paths stamp collected_at server-side today, so this validation
  # exists for the day that stops being true (a newly permitted parameter, a
  # console session, a data migration, admin tooling).
  describe "collected_at is never in the future (#903)" do
    it "rejects a future collection timestamp" do
      evidence = build(:evidence, collected_at: 1.day.from_now)

      expect(evidence).not_to be_valid
      expect(evidence.errors[:collected_at]).to include("cannot be in the future")
    end

    it "rejects a timestamp only slightly in the future" do
      evidence = build(:evidence, collected_at: 5.minutes.from_now)

      expect(evidence).not_to be_valid
    end

    it "accepts now and the past" do
      expect(build(:evidence, collected_at: Time.current)).to be_valid
      expect(build(:evidence, collected_at: 3.years.ago)).to be_valid
    end

    it "accepts a blank collection timestamp" do
      expect(build(:evidence, collected_at: nil)).to be_valid
    end

    # A validation that locks the record it is meant to protect helps nobody:
    # a row that already carries a bad value must still be correctable.
    it "does not block editing a record that already holds a future value" do
      evidence = build(:evidence, collected_at: 2.days.from_now)
      evidence.save!(validate: false)

      evidence.title = "Corrected title"

      expect(evidence).to be_valid
      expect(evidence.save).to be true
    end

    it "still rejects moving a stored timestamp further into the future" do
      evidence = create(:evidence, collected_at: 1.hour.ago)

      evidence.collected_at = 1.day.from_now

      expect(evidence).not_to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:authorization_boundary).optional }
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

      expect(evidence.linked_control_ids).to contain_exactly("ac-1", "ac-2")
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
