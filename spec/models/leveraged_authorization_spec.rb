require "rails_helper"

RSpec.describe LeveragedAuthorization, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:leveraging_boundary).class_name("AuthorizationBoundary") }
    it { is_expected.to belong_to(:leveraged_boundary).class_name("AuthorizationBoundary").optional }
    it { is_expected.to have_many(:leveraged_authorization_components).dependent(:destroy) }
  end

  describe "validations" do
    subject(:la) { build(:leveraged_authorization) }

    it { is_expected.to validate_presence_of(:name) }

    it "requires a known crm_type" do
      la.crm_type = "fantasy"
      expect(la).not_to be_valid
    end

    it "auto-assigns uuid if blank" do
      la.uuid = nil
      la.valid?
      expect(la.uuid).to match(BackMatterResource::UUID_V4_REGEX)
    end

    it "rejects self-reference" do
      b = create(:authorization_boundary)
      la = build(:leveraged_authorization, leveraging_boundary: b, leveraged_boundary: b)
      expect(la).not_to be_valid
      expect(la.errors[:leveraged_boundary]).to be_present
    end

    it "detects cycles" do
      a = create(:authorization_boundary)
      b = create(:authorization_boundary)
      create(:leveraged_authorization, leveraging_boundary: a, leveraged_boundary: b)
      # Creating a second link where b leverages a would cycle back to a.
      la = build(:leveraged_authorization, leveraging_boundary: b, leveraged_boundary: a)
      expect(la).not_to be_valid
      expect(la.errors[:leveraged_boundary]).to be_present
    end
  end

  describe "#scenario" do
    it { expect(build(:leveraged_authorization, crm_type: "oscal_with_access").scenario).to eq(1) }
    it { expect(build(:leveraged_authorization, :oscal_no_access).scenario).to eq(2) }
    it { expect(build(:leveraged_authorization, :legacy).scenario).to eq(3) }
  end
end
