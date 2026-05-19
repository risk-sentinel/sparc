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

  # Issues #491 + #494 -- two-hop NIST enrichment with Converters
  # aws_security_hub_to_nist (direct) and aws_config_to_nist (chained
  # via the SecHub -> AWS Config Rule bridge in lib/data_mappings/).
  describe "NIST enrichment via two-hop chain (#491 + #494)" do
    let(:iam_cd) { fixture_dir.join("iam-cd-realistic.json").read }

    let!(:sec_hub_converter) do
      Converter.create!(
        name: "AWS Security Hub → NIST SP 800-53 rev5",
        converter_type: "aws_security_hub_to_nist",
        source_framework: "AWS Security Hub",
        target_framework: "NIST SP 800-53",
        version: "test", description: "spec", status: "complete"
      )
    end

    let!(:aws_config_converter) do
      Converter.create!(
        name: "AWS Config Rule → NIST SP 800-53",
        converter_type: "aws_config_to_nist",
        source_framework: "AWS Config Rules",
        target_framework: "NIST SP 800-53",
        version: "test", description: "spec", status: "complete"
      )
    end

    let(:tree) do
      [ tree_entry(path: "component-definitions/iam/iam-cd.json", sha: "sha-iam") ]
    end

    before do
      allow(SparcConfig).to receive(:aws_labs_oscal_versions).and_return([ "1.1.2" ])
      allow(client).to receive(:list_component_definition_files).and_return(tree)
      allow(client).to receive(:fetch_file)
        .with(path: "component-definitions/iam/iam-cd.json")
        .and_return(file_entry(path: "component-definitions/iam/iam-cd.json", sha: "sha-iam", content: iam_cd))

      # Hop 1: IAM.3 mapped directly via aws_security_hub_to_nist.
      [
        { source: "IAM.3", target: "ac-2.1" },
        { source: "IAM.3", target: "ac-3.15" }
      ].each_with_index do |r, i|
        ConverterEntry.create!(
          converter: sec_hub_converter,
          source_id: r[:source], target_id: r[:target],
          relationship: "intersects", category: "aws_direct",
          row_order: i + 1, remarks: "title=Rotate | aws_config_rule=access-keys-rotated | source=aws_direct"
        )
      end

      # Hop 2: IAM.7 has no direct row in sec_hub_converter, but the
      # bridge gives its Config Rule (iam-password-policy), and the
      # aws_config_converter maps that rule to NIST.
      ConverterEntry.create!(
        converter: aws_config_converter,
        source_id: "iam-password-policy",
        target_id: "ia-5.1",
        relationship: "intersects", category: "mitre_vendored",
        row_order: 1, remarks: "aws_config_rule_source_identifier=IAM_PASSWORD_POLICY"
      )

      # Stub the bridge so we don't depend on the live JSON for fixture data.
      bridge = { "IAM.3" => "access-keys-rotated", "IAM.7" => "iam-password-policy", "IAM.99999" => nil }
      allow_any_instance_of(described_class).to receive(:sec_hub_config_rule_bridge).and_return(bridge)
    end

    it "hop 1: writes aws_direct fields for SecHub controls in aws_security_hub_to_nist" do
      described_class.new(client: client).run

      doc = CdefDocument.aws_labs_sourced.last
      iam3 = doc.cdef_controls.find_by(control_id: "IAM.3")
      fields = iam3.cdef_control_fields.pluck(:field_name, :field_value).to_h
      expect(fields["aws_security_hub_id"]).to eq("IAM.3")
      expect(fields["nist_oscal_ids"]).to eq("ac-2.1,ac-3.15")
      expect(fields["nist_primary_id"]).to eq("ac-2.1")
      expect(fields["nist_mapping_source"]).to eq("aws_direct")
    end

    it "hop 2: chains through aws_config_to_nist when no aws_direct row exists" do
      described_class.new(client: client).run

      doc = CdefDocument.aws_labs_sourced.last
      iam7 = doc.cdef_controls.find_by(control_id: "IAM.7")
      fields = iam7.cdef_control_fields.pluck(:field_name, :field_value).to_h
      expect(fields["nist_oscal_ids"]).to eq("ia-5.1")
      expect(fields["nist_mapping_source"]).to eq("via_config_rule")
      expect(fields["aws_config_rule"]).to eq("iam-password-policy")
    end

    it "leaves controls with neither hop matching un-enriched" do
      described_class.new(client: client).run

      doc = CdefDocument.aws_labs_sourced.last
      unmapped = doc.cdef_controls.find_by(control_id: "IAM.99999")
      expect(unmapped.cdef_control_fields.where(field_name: "nist_oscal_ids")).to be_empty
    end

    it "preserves the original SecHub control_id (does not mutate it)" do
      described_class.new(client: client).run
      doc = CdefDocument.aws_labs_sourced.last
      expect(doc.cdef_controls.pluck(:control_id)).to include("IAM.3", "IAM.7", "IAM.99999")
    end

    it "no-ops gracefully when aws_security_hub_to_nist Converter is missing" do
      sec_hub_converter.destroy!
      expect { described_class.new(client: client).run }.not_to raise_error
      doc = CdefDocument.aws_labs_sourced.last
      iam3 = doc.cdef_controls.find_by(control_id: "IAM.3")
      expect(iam3.cdef_control_fields.where(field_name: "nist_oscal_ids")).to be_empty
    end

    it "skips hop 2 gracefully when aws_config_to_nist Converter is missing" do
      aws_config_converter.destroy!
      described_class.new(client: client).run
      doc = CdefDocument.aws_labs_sourced.last
      iam7 = doc.cdef_controls.find_by(control_id: "IAM.7")
      # No fallback available, but hop 1 controls (IAM.3) still enriched.
      expect(iam7.cdef_control_fields.where(field_name: "nist_oscal_ids")).to be_empty
      iam3 = doc.cdef_controls.find_by(control_id: "IAM.3")
      expect(iam3.cdef_control_fields.where(field_name: "nist_oscal_ids")).not_to be_empty
    end

    it "marks enrichment fields as non-editable" do
      described_class.new(client: client).run
      doc = CdefDocument.aws_labs_sourced.last
      iam3 = doc.cdef_controls.find_by(control_id: "IAM.3")
      expect(iam3.cdef_control_fields.pluck(:editable).uniq).to eq([ false ])
    end
  end
end
