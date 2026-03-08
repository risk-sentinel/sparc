require "rails_helper"

RSpec.describe EvidenceControlLink, type: :model do
  describe "validations" do
    subject { build(:evidence_control_link) }

    it { is_expected.to validate_presence_of(:control_id) }

    it "validates uniqueness of control_id scoped to evidence, document_type, document_id" do
      link = create(:evidence_control_link)
      duplicate = build(:evidence_control_link,
        evidence: link.evidence,
        control_id: link.control_id,
        document_type: link.document_type,
        document_id: link.document_id)
      expect(duplicate).not_to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:evidence) }
  end

  describe "DOCUMENT_TYPES" do
    it "includes all expected document types" do
      expect(EvidenceControlLink::DOCUMENT_TYPES).to contain_exactly(
        "SspDocument", "SarDocument", "SapDocument", "CdefDocument", "PoamDocument"
      )
    end
  end

  describe "#document" do
    it "returns nil when document_type and document_id are blank" do
      link = build(:evidence_control_link, document_type: nil, document_id: nil)
      expect(link.document).to be_nil
    end
  end
end
