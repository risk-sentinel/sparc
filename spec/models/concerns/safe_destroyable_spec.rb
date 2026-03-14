require "rails_helper"

RSpec.describe SafeDestroyable do
  describe "deletion protection" do
    it "blocks deletion of profile with linked SSPs" do
      profile = create(:profile_document)
      create(:ssp_document, profile_document: profile)
      expect(profile.destroy).to be_falsey
      expect(profile.errors[:base]).to be_present
    end

    it "allows deletion when no dependencies exist" do
      profile = create(:profile_document)
      expect(profile.destroy).to be_truthy
    end

    it "includes error message with dependency count" do
      profile = create(:profile_document)
      create(:ssp_document, profile_document: profile)
      profile.destroy
      expect(profile.errors[:base].first).to match(/Cannot delete/)
    end
  end
end
