require "rails_helper"

RSpec.describe ProfileDocument, type: :model do
  describe "validations" do
    subject { build(:profile_document) }

    it { is_expected.to validate_presence_of(:name) }
  end

  describe "associations" do
    it { is_expected.to have_many(:profile_controls).dependent(:delete_all) }
    it { is_expected.to belong_to(:control_catalog).optional }
    it { is_expected.to have_one_attached(:file) }
  end

  describe "concerns" do
    it "includes OscalMetadata" do
      expect(ProfileDocument.ancestors).to include(OscalMetadata)
    end

    it "includes SafeDestroyable" do
      expect(ProfileDocument.ancestors).to include(SafeDestroyable)
    end
  end

  describe "enums" do
    it "defines status enum" do
      expect(ProfileDocument.statuses).to eq(
        "pending" => "pending",
        "processing" => "processing",
        "completed" => "completed",
        "failed" => "failed"
      )
    end
  end

  describe "deletion protection" do
    it "prevents deletion when an SspDocument references the profile" do
      profile = create(:profile_document)
      create(:ssp_document, profile_document: profile)

      expect(profile.destroy).to be_falsey
      expect(profile.errors[:base].first).to match(/Cannot delete profile document/)
    end

    it "prevents deletion when a SapDocument references the profile" do
      profile = create(:profile_document)
      create(:sap_document, profile_document: profile)

      expect(profile.destroy).to be_falsey
      expect(profile.errors[:base].first).to match(/Cannot delete profile document/)
    end

    it "allows deletion when no documents are linked" do
      profile = create(:profile_document)
      expect(profile.destroy).to be_truthy
    end
  end

  describe "#to_json_data" do
    let(:profile) { create(:profile_document, name: "Test Profile", baseline_level: "MODERATE") }

    it "returns a hash with document metadata and controls" do
      data = profile.to_json_data

      expect(data[:document_name]).to eq("Test Profile")
      expect(data[:baseline_level]).to eq("MODERATE")
      expect(data[:controls]).to be_an(Array)
    end
  end
end
