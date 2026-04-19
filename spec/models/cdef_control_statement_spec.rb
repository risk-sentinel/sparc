require "rails_helper"

RSpec.describe CdefControlStatement, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:cdef_control) }
  end

  describe "validations" do
    subject { build(:cdef_control_statement) }

    it { is_expected.to validate_presence_of(:statement_id) }
    it { is_expected.to validate_presence_of(:uuid) }

    it "validates uniqueness of statement_id scoped to cdef_control" do
      existing = create(:cdef_control_statement, statement_id: "ac-1_smt.a")
      dup = build(:cdef_control_statement, cdef_control: existing.cdef_control, statement_id: "ac-1_smt.a")
      expect(dup).not_to be_valid
    end
  end

  describe "EDITABLE_ATTRIBUTES" do
    it "exposes only implementation response fields" do
      expect(CdefControlStatement::EDITABLE_ATTRIBUTES).to match_array(
        %i[implementation_prose remarks set_parameters_data]
      )
    end
  end
end
