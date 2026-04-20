require "rails_helper"

RSpec.describe LeveragedAuthorizationComponent, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:leveraged_authorization) }
  end

  describe "validations" do
    subject { build(:leveraged_authorization_component) }

    it { is_expected.to validate_presence_of(:title) }

    it "restricts component_type to the OSCAL enum" do
      comp = build(:leveraged_authorization_component, component_type: "fantasy")
      expect(comp).not_to be_valid
    end

    it "auto-assigns uuid" do
      comp = build(:leveraged_authorization_component, uuid: nil)
      comp.valid?
      expect(comp.uuid).to match(BackMatterResource::UUID_V4_REGEX)
    end
  end
end
