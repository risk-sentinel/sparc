require "rails_helper"

RSpec.describe SspControlStatementInheritance, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:ssp_control_statement) }
    it { is_expected.to belong_to(:source) }
  end

  describe "validations" do
    subject(:link) { build(:ssp_control_statement_inheritance) }

    it { is_expected.to validate_presence_of(:source_uuid) }

    it "accepts only known source types" do
      link.source_type = "FakeType"
      expect(link).not_to be_valid
    end

    it "rejects non-v4 source UUIDs" do
      link.source_uuid = "not-a-uuid"
      expect(link).not_to be_valid
    end

    it "enforces uniqueness of (target_stmt, source_type, source_id)" do
      existing = create(:ssp_control_statement_inheritance)
      dup = build(:ssp_control_statement_inheritance,
                  ssp_control_statement: existing.ssp_control_statement,
                  source: existing.source,
                  source_uuid: existing.source_uuid)
      expect(dup).not_to be_valid
    end
  end

  describe "#effective_prose" do
    it "returns source prose when not overridden" do
      source = create(:cdef_control_statement, implementation_prose: "from CDEF")
      link = create(:ssp_control_statement_inheritance, source: source)
      expect(link.effective_prose).to eq("from CDEF")
    end

    it "returns overridden_prose when overridden" do
      link = create(:ssp_control_statement_inheritance, :overridden,
                    overridden_prose: "local edit")
      expect(link.effective_prose).to eq("local edit")
    end
  end

  describe "#override!" do
    it "flips overridden and snapshots the edit" do
      link = create(:ssp_control_statement_inheritance)
      link.override!("new prose")
      expect(link.reload).to have_attributes(overridden: true, overridden_prose: "new prose")
    end
  end

  describe "#reset_to_source!" do
    it "clears the override and resyncs the target prose to the source" do
      source = create(:cdef_control_statement, implementation_prose: "latest CDEF prose")
      target = create(:ssp_control_statement, implementation_prose: "stale override")
      link = create(:ssp_control_statement_inheritance, :overridden,
                    ssp_control_statement: target,
                    source: source,
                    overridden_prose: "stale override")

      link.reset_to_source!

      expect(link.reload).to have_attributes(overridden: false, overridden_prose: nil)
      expect(target.reload.implementation_prose).to eq("latest CDEF prose")
    end
  end
end
