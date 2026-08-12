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

  # #934 / AU-10 — the one place collection provenance is written, so a fourth
  # creation path cannot repeat the omission this issue was filed for.
  describe "#stamp_collection!" do
    it "records the actor as both the historical name and the reference" do
      user = create(:user, display_name: "Ada Lovelace")
      evidence = build(:evidence, collected_by: nil, collected_at: nil)

      evidence.stamp_collection!(actor: user)

      expect(evidence.collected_by).to eq("Ada Lovelace")
      expect(evidence.collected_by_user).to eq(user)
      expect(evidence.collected_at).to be_within(1.minute).of(Time.current)
      expect(evidence.collected_at.zone).to eq("UTC")
    end

    it "falls back to email when the account has no name to show" do
      user = create(:user, display_name: nil, first_name: nil, last_name: nil,
                    email: "grace@example.gov")
      evidence = build(:evidence)

      evidence.stamp_collection!(actor: user)

      expect(evidence.collected_by).to eq("grace@example.gov")
    end

    it "names a non-user collector and leaves the reference null" do
      evidence = build(:evidence)

      evidence.stamp_collection!(actor: nil, label: "System (authoritative fetch)")

      expect(evidence.collected_by).to eq("System (authoritative fetch)")
      expect(evidence.collected_by_user).to be_nil
      expect(evidence.collected_at).to be_present
    end

    it "assigns without saving, leaving each caller its own error handling" do
      evidence = build(:evidence)

      evidence.stamp_collection!(actor: create(:user))

      expect(evidence).to be_new_record
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
