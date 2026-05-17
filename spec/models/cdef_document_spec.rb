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

  # Issue #466 — AWS Labs provenance + read-only guards
  describe "AWS Labs provenance" do
    let(:aws_cdef) do
      create(:cdef_document,
             name: "AWS S3",
             import_metadata: {
               "source_type" => "aws_labs",
               "source_url" => "https://github.com/awslabs/oscal-content-for-aws-services/blob/main/component-definitions/s3/s3-cd.json",
               "source_sha" => "abc123"
             })
    end

    let(:user_cdef) { create(:cdef_document, name: "User CDEF") }

    it "marks aws_labs_source? true when source_type metadata is aws_labs" do
      expect(aws_cdef.aws_labs_source?).to be(true)
      expect(user_cdef.aws_labs_source?).to be(false)
    end

    it "returns false for editable? when AWS-sourced" do
      expect(aws_cdef.editable?).to be(false)
      expect(user_cdef.editable?).to be(true)
    end

    it "exposes source_url for AWS-sourced rows only" do
      expect(aws_cdef.source_url).to start_with("https://github.com/awslabs/")
      expect(user_cdef.source_url).to be_nil
    end

    it "scope :aws_labs_sourced returns only AWS rows" do
      aws_cdef
      user_cdef
      expect(CdefDocument.aws_labs_sourced).to contain_exactly(aws_cdef)
    end

    it "supports cloned_from association" do
      clone = create(:cdef_document, name: "Clone", cloned_from: aws_cdef)
      expect(clone.cloned_from).to eq(aws_cdef)
      expect(aws_cdef.clones).to include(clone)
    end
  end
end
