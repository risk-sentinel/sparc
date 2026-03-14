require "rails_helper"

RSpec.describe CdefDocument, type: :model do
  describe "validations" do
    subject { build(:cdef_document) }

    it { is_expected.to validate_presence_of(:name) }
  end

  describe "associations" do
    it { is_expected.to have_many(:cdef_controls).dependent(:delete_all) }
    it { is_expected.to have_one_attached(:file) }
  end

  describe "concerns" do
    it "includes OscalMetadata" do
      expect(CdefDocument.ancestors).to include(OscalMetadata)
    end

    it "includes SafeDestroyable" do
      expect(CdefDocument.ancestors).to include(SafeDestroyable)
    end
  end

  describe "enums" do
    it "defines status enum" do
      expect(CdefDocument.statuses).to eq(
        "pending" => "pending",
        "processing" => "processing",
        "completed" => "completed",
        "failed" => "failed"
      )
    end
  end

  describe "deletion protection" do
    it "prevents deletion when an SspDocumentCdefDocument reference exists" do
      cdef = create(:cdef_document)
      create(:ssp_document_cdef_document, cdef_document: cdef)

      expect(cdef.destroy).to be_falsey
      expect(cdef.errors[:base].first).to match(/Cannot delete cdef document/)
    end

    it "prevents deletion when a BoundaryCdefDocument reference exists" do
      cdef = create(:cdef_document)
      create(:boundary_cdef_document, cdef_document: cdef)

      expect(cdef.destroy).to be_falsey
      expect(cdef.errors[:base].first).to match(/Cannot delete cdef document/)
    end

    it "allows deletion when no references exist" do
      cdef = create(:cdef_document)
      expect(cdef.destroy).to be_truthy
    end
  end

  describe "#to_json_data" do
    let(:cdef) { create(:cdef_document, name: "Test CDEF", cdef_type: "disa_stig") }

    it "returns a hash with document metadata and controls" do
      data = cdef.to_json_data

      expect(data[:document_name]).to eq("Test CDEF")
      expect(data[:cdef_type]).to eq("disa_stig")
      expect(data[:controls]).to be_an(Array)
    end
  end
end
