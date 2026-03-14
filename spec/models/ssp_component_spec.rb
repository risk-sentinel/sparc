require "rails_helper"

RSpec.describe SspComponent, type: :model do
  describe "validations" do
    subject { build(:ssp_component) }

    it { is_expected.to validate_presence_of(:uuid) }
    it { is_expected.to validate_presence_of(:component_type) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:description) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:ssp_document) }
    it { is_expected.to belong_to(:cdef_document).optional }
  end

  describe ".this_system" do
    it "returns only this-system components" do
      ssp = create(:ssp_document)
      create(:ssp_component, ssp_document: ssp, component_type: "this-system")
      create(:ssp_component, ssp_document: ssp, component_type: "software")

      expect(SspComponent.this_system.count).to eq(1)
    end
  end
end
