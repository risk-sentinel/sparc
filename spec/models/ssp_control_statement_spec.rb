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
        %i[implementation_prose remarks responsible_roles_data set_parameters_data
           implementation_status expected_completion]
      )
    end

    it "does NOT include catalog-derived read-only fields" do
      %i[statement_id label parent_statement_id].each do |attr|
        expect(SspControlStatement::EDITABLE_ATTRIBUTES).not_to include(attr)
      end
    end
  end

  # #1312 — each item's own status, origination and expected completion.
  describe "item fields" do
    let(:control) { create(:ssp_control) }

    def item(**attrs)
      control.ssp_control_statements.build(statement_id: "ac-1_smt.a", uuid: SecureRandom.uuid, **attrs)
    end

    it "accepts OSCAL's five implementation states and nothing else" do
      SspControlStatement::IMPLEMENTATION_STATUSES.each { expect(item(implementation_status: _1)).to be_valid }
      expect(item(implementation_status: "Deferred")).not_to be_valid
      expect(item(implementation_status: "")).to be_valid.and(have_attributes(implementation_status: nil))
    end

    it "keeps OSCAL's originations in OSCAL's order, dropping blanks and repeats" do
      stmt = item(control_origination: [ "", "inherited", "organization", "inherited" ])
      expect(stmt).to be_valid
      expect(stmt.control_origination).to eq(%w[organization inherited])
      expect(item(control_origination: [ "hybrid" ])).not_to be_valid
    end

    it "tells fully from partly inherited" do
      expect(item(control_origination: %w[inherited])).to be_fully_inherited
      expect(item(control_origination: %w[inherited system-specific]).tap(&:valid?)).to be_partially_inherited
      expect(item(control_origination: %w[system-specific]).tap(&:valid?)).not_to be_partially_inherited
    end

    it "refuses an expected completion that is not a date" do
      expect(item(expected_completion: "next spring")).not_to be_valid
      expect(item(expected_completion: "2027-01-31")).to be_valid
    end

    it "calls planned and partial not in place, and alternative in place" do
      expect(item(implementation_status: "planned")).to be_not_in_place
      expect(item(implementation_status: "partial")).to be_not_in_place
      expect(item(implementation_status: "alternative")).not_to be_not_in_place
    end
  end
end
