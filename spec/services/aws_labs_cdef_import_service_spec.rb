require "rails_helper"

RSpec.describe AwsLabsCdefImportService do
  let(:fixture_dir) { Rails.root.join("spec/fixtures/files/components/aws_labs") }
  let(:s3_v1_0_0) { fixture_dir.join("s3-cd-v1.0.0.json").read }
  let(:s3_v1_0_1) { fixture_dir.join("s3-cd-v1.0.1.json").read }
  let(:ec2)       { fixture_dir.join("ec2-cd.json").read }

  let(:client) { instance_double(AwsLabsCdefSourceClient) }

  before do
    ENV["SPARC_AWS_LABS_CDEF_ENABLED"] = "true"
    allow(SparcConfig).to receive(:aws_labs_cdef_enabled?).and_return(true)
    allow(SparcConfig).to receive(:aws_labs_cdef_repo).and_return("awslabs/oscal-content-for-aws-services")
    allow(SparcConfig).to receive(:aws_labs_cdef_branch).and_return("main")
    allow(client).to receive(:current_commit_sha).and_return("commit-sha-aaaa")
  end

  after do
    ENV.delete("SPARC_AWS_LABS_CDEF_ENABLED")
  end

  def tree_entry(path:, sha:)
    { "type" => "blob", "path" => path, "sha" => sha }
  end

  def file_entry(path:, sha:, content:)
    {
      path: path,
      sha: sha,
      html_url: "https://github.com/awslabs/oscal-content-for-aws-services/blob/main/#{path}",
      content: content
    }
  end

  context "when SPARC_AWS_LABS_CDEF_ENABLED is false" do
    it "is a no-op and returns an empty result" do
      allow(SparcConfig).to receive(:aws_labs_cdef_enabled?).and_return(false)
      service = described_class.new(client: client)
      expect(client).not_to receive(:list_component_definition_files)

      result = service.run
      expect(result.imported).to eq(0)
      expect(result.discovered).to eq(0)
    end
  end

  context "when the tree is unchanged (ETag 304)" do
    it "returns an empty result without fetching files" do
      allow(client).to receive(:list_component_definition_files).and_return(nil)
      service = described_class.new(client: client)

      expect(client).not_to receive(:fetch_file)
      result = service.run
      expect(result.discovered).to eq(0)
    end
  end

  context "with a fresh tree of three files (two versions of S3, one EC2)" do
    let(:tree) do
      [
        tree_entry(path: "component-definitions/s3/s3-cd-v1.0.0.json", sha: "sha-s3-old"),
        tree_entry(path: "component-definitions/s3/s3-cd-v1.0.1.json", sha: "sha-s3-new"),
        tree_entry(path: "component-definitions/ec2/ec2-cd.json",      sha: "sha-ec2")
      ]
    end

    before do
      allow(client).to receive(:list_component_definition_files).and_return(tree)
      allow(client).to receive(:fetch_file).with(path: "component-definitions/s3/s3-cd-v1.0.0.json")
        .and_return(file_entry(path: "component-definitions/s3/s3-cd-v1.0.0.json", sha: "sha-s3-old", content: s3_v1_0_0))
      allow(client).to receive(:fetch_file).with(path: "component-definitions/s3/s3-cd-v1.0.1.json")
        .and_return(file_entry(path: "component-definitions/s3/s3-cd-v1.0.1.json", sha: "sha-s3-new", content: s3_v1_0_1))
      allow(client).to receive(:fetch_file).with(path: "component-definitions/ec2/ec2-cd.json")
        .and_return(file_entry(path: "component-definitions/ec2/ec2-cd.json", sha: "sha-ec2", content: ec2))
    end

    it "keeps the highest version per (service, oscal-version) and imports the rest" do
      allow(SparcConfig).to receive(:aws_labs_oscal_versions).and_return([ "1.1.2", "1.0.4" ])
      service = described_class.new(client: client)

      result = service.run

      # 2 candidates kept: S3 v1.0.1 (higher than v1.0.0) and EC2 v2.1.0
      expect(result.imported).to eq(2)
      expect(result.skipped_unchanged).to eq(0)
      expect(result.errors).to be_empty
      expect(CdefDocument.aws_labs_sourced.count).to eq(2)

      s3 = CdefDocument.aws_labs_sourced.find_by("import_metadata->>'source_path' = ?", "component-definitions/s3/s3-cd-v1.0.1.json")
      expect(s3).to be_present
      expect(s3.import_metadata["source_sha"]).to eq("sha-s3-new")
      expect(s3.import_metadata["source_oscal_version"]).to eq("1.1.2")
      expect(s3.editable?).to be(false)
      expect(s3.cdef_controls.count).to eq(2) # ac-3, sc-7
    end

    it "filters out CDEFs whose oscal-version is not allowed" do
      allow(SparcConfig).to receive(:aws_labs_oscal_versions).and_return([ "1.1.2" ])
      service = described_class.new(client: client)

      result = service.run

      # EC2 is oscal 1.0.4, filtered out
      expect(result.imported).to eq(1)
      expect(CdefDocument.aws_labs_sourced.count).to eq(1)
    end

    it "is idempotent on re-run with the same shas" do
      allow(SparcConfig).to receive(:aws_labs_oscal_versions).and_return([ "1.1.2", "1.0.4" ])
      described_class.new(client: client).run

      result = described_class.new(client: client).run
      expect(result.imported).to eq(0)
      expect(result.skipped_unchanged).to eq(2)
    end

    it "supersedes prior rows when source_sha changes" do
      allow(SparcConfig).to receive(:aws_labs_oscal_versions).and_return([ "1.1.2", "1.0.4" ])
      described_class.new(client: client).run

      # Same path, but sha shifts.
      new_tree = [
        tree_entry(path: "component-definitions/s3/s3-cd-v1.0.1.json", sha: "sha-s3-newer")
      ]
      allow(client).to receive(:list_component_definition_files).and_return(new_tree)
      allow(client).to receive(:fetch_file).with(path: "component-definitions/s3/s3-cd-v1.0.1.json")
        .and_return(file_entry(path: "component-definitions/s3/s3-cd-v1.0.1.json", sha: "sha-s3-newer", content: s3_v1_0_1))

      result = described_class.new(client: client).run
      expect(result.imported).to eq(1)
      expect(result.superseded).to eq(1)

      prior = CdefDocument.aws_labs_sourced
        .where("import_metadata->>'source_sha' = ?", "sha-s3-new").first
      expect(prior.import_metadata["superseded_at"]).to be_present
      expect(prior.import_metadata["superseded_by_sha"]).to eq("sha-s3-newer")
    end

    it "does not touch user clones of an AWS-sourced CDEF on re-run" do
      allow(SparcConfig).to receive(:aws_labs_oscal_versions).and_return([ "1.1.2", "1.0.4" ])
      described_class.new(client: client).run

      original = CdefDocument.aws_labs_sourced.find_by!("import_metadata->>'source_path' = ?",
                                                        "component-definitions/s3/s3-cd-v1.0.1.json")
      clone = DocumentDuplicationService.new(original).duplicate
      clone.update!(cloned_from_id: original.id, name: "User clone of S3")

      clone_updated_at = clone.updated_at

      # Re-run with same data — clone must be untouched.
      described_class.new(client: client).run
      expect(clone.reload.updated_at).to be_within(1.second).of(clone_updated_at)
      expect(clone.import_metadata["source_type"]).to be_nil
      expect(clone.editable?).to be(true)
    end
  end
end
