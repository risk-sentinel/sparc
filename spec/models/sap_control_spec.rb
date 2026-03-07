require "rails_helper"

RSpec.describe SapControl, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:sap_document) }
    it { is_expected.to have_many(:sap_control_fields).dependent(:delete_all) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:control_id) }
  end

  describe "#compute_control_family" do
    it "computes family from control_id" do
      control = create(:sap_control, control_id: "AC-1", control_family: nil)
      expect(control.control_family).to eq("AC")
    end

    it "preserves existing control_family" do
      control = create(:sap_control, control_id: "AC-1", control_family: "CUSTOM")
      expect(control.control_family).to eq("CUSTOM")
    end
  end

  describe "#to_hash" do
    let(:control) { create(:sap_control, control_id: "AC-2", assessment_method: "test") }

    it "returns a serializable hash" do
      hash = control.to_hash
      expect(hash[:control_id]).to eq("AC-2")
      expect(hash[:assessment_method]).to eq("test")
      expect(hash[:fields]).to be_an(Array)
    end
  end
end
