require "rails_helper"

RSpec.describe SspControlStatement, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:ssp_control) }
    it { is_expected.to have_many(:sar_findings).dependent(:nullify) }
    it { is_expected.to have_many(:poam_items).dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:ssp_control_statement) }

    it { is_expected.to validate_presence_of(:statement_id) }
    it { is_expected.to validate_presence_of(:uuid) }

    it "validates uniqueness of statement_id scoped to ssp_control" do
      existing = create(:ssp_control_statement, statement_id: "ac-1_smt.a")
      dup = build(:ssp_control_statement, ssp_control: existing.ssp_control, statement_id: "ac-1_smt.a")
      expect(dup).not_to be_valid
    end

    it "rejects non-v4 UUIDs" do
      stmt = build(:ssp_control_statement, uuid: "not-a-uuid")
      expect(stmt).not_to be_valid
    end
  end

  describe "EDITABLE_ATTRIBUTES" do
    it "exposes only the user-editable response fields" do
      expect(SspControlStatement::EDITABLE_ATTRIBUTES).to match_array(
        %i[implementation_prose remarks responsible_roles_data set_parameters_data]
      )
    end

    it "does NOT include catalog-derived read-only fields" do
      %i[statement_id label parent_statement_id].each do |attr|
        expect(SspControlStatement::EDITABLE_ATTRIBUTES).not_to include(attr)
      end
    end
  end
end
