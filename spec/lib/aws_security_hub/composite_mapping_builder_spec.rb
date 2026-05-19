# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/aws_security_hub/composite_mapping_builder")

RSpec.describe AwsSecurityHub::CompositeMappingBuilder do
  let(:aws_direct) do
    {
      "mappings" => [
        {
          "sec_hub_id"      => "IAM.3",
          "title"           => "Rotate access keys",
          "nist_oscal_ids"  => [ "ac-2.1", "ac-2.3" ],
          "aws_config_rule" => "access-keys-rotated"
        },
        {
          "sec_hub_id"      => "ACM.2",
          "title"           => "RSA 2048+",
          "nist_oscal_ids"  => [],
          "aws_config_rule" => "acm-certificate-rsa-check"
        },
        {
          "sec_hub_id"      => "Backup.2",
          "title"           => "Tag governance",
          "nist_oscal_ids"  => [],
          "aws_config_rule" => nil
        },
        {
          "sec_hub_id"      => "",
          "title"           => "blank",
          "nist_oscal_ids"  => [ "ac-1" ]
        }
      ]
    }
  end

  let(:mitre) do
    {
      "mappings" => [
        {
          "aws_config_rule_name" => "acm-certificate-rsa-check",
          "nist_rev4_raw"        => [ "SC-12" ],
          "nist_oscal_ids"       => [ "sc-12" ]
        },
        {
          "aws_config_rule_name" => "unused-rule",
          "nist_oscal_ids"       => [ "ia-2" ]
        }
      ]
    }
  end

  describe ".build" do
    it "emits one row per NIST id and tags source provenance" do
      rows, stats = described_class.build(aws_direct: aws_direct, mitre: mitre)

      iam_rows = rows.select { |r| r["source_id"] == "IAM.3" }
      expect(iam_rows.length).to eq(2)
      expect(iam_rows.map { |r| r["target_id"] }).to contain_exactly("ac-2.1", "ac-2.3")
      expect(iam_rows.first["category"]).to eq("aws_direct")
    end

    it "falls back to MITRE when AWS-direct has no NIST mapping" do
      rows, _stats = described_class.build(aws_direct: aws_direct, mitre: mitre)

      acm_rows = rows.select { |r| r["source_id"] == "ACM.2" }
      expect(acm_rows.length).to eq(1)
      expect(acm_rows.first["target_id"]).to eq("sc-12")
      expect(acm_rows.first["category"]).to eq("mitre_fallback")
    end

    it "emits no rows when neither source has a mapping" do
      rows, _stats = described_class.build(aws_direct: aws_direct, mitre: mitre)

      expect(rows.map { |r| r["source_id"] }).not_to include("Backup.2")
    end

    it "skips entries with blank sec_hub_id" do
      rows, _stats = described_class.build(aws_direct: aws_direct, mitre: mitre)

      expect(rows.map { |r| r["source_id"] }).not_to include("")
    end

    it "returns stats counting aws_direct, mitre_fallback, and unmapped" do
      _rows, stats = described_class.build(aws_direct: aws_direct, mitre: mitre)

      expect(stats).to eq(aws_direct: 1, mitre_fallback: 1, unmapped: 1)
    end

    it "includes remarks with title, config rule, and source" do
      rows, _stats = described_class.build(aws_direct: aws_direct, mitre: mitre)

      iam_remarks = rows.find { |r| r["source_id"] == "IAM.3" }["remarks"]
      expect(iam_remarks).to include("title=Rotate access keys")
      expect(iam_remarks).to include("aws_config_rule=access-keys-rotated")
      expect(iam_remarks).to include("source=aws_direct")
    end

    it "annotates fallback remarks with MITRE rev4 ids for audit" do
      rows, _stats = described_class.build(aws_direct: aws_direct, mitre: mitre)

      acm_remarks = rows.find { |r| r["source_id"] == "ACM.2" }["remarks"]
      expect(acm_remarks).to include("source=mitre_fallback")
      expect(acm_remarks).to include("mitre_rev4=SC-12")
    end

    it "sets relationship to intersects on every row" do
      rows, _stats = described_class.build(aws_direct: aws_direct, mitre: mitre)

      expect(rows.map { |r| r["relationship"] }.uniq).to eq([ "intersects" ])
    end
  end

  describe ".from_paths" do
    it "reads JSON from disk and composes the same result" do
      aws_path   = Tempfile.new([ "aws_direct", ".json" ])
      mitre_path = Tempfile.new([ "mitre", ".json" ])
      aws_path.write(JSON.generate(aws_direct))
      mitre_path.write(JSON.generate(mitre))
      aws_path.close
      mitre_path.close

      rows, stats = described_class.from_paths(aws_direct_path: aws_path.path, mitre_path: mitre_path.path)
      expect(rows.length).to eq(3)
      expect(stats[:aws_direct]).to eq(1)
      expect(stats[:mitre_fallback]).to eq(1)
    ensure
      aws_path&.unlink
      mitre_path&.unlink
    end
  end

  describe "real vendored + scraped data integration" do
    let(:aws_path)   { Rails.root.join("lib/data_mappings/aws_security_hub_to_nist.json") }
    let(:mitre_path) { Rails.root.join("lib/data_mappings/mitre_aws_config_to_nist.json") }

    it "composes the live data files without raising and produces >300 rows" do
      rows, stats = described_class.from_paths(aws_direct_path: aws_path, mitre_path: mitre_path)

      expect(rows.length).to be > 300
      expect(stats[:aws_direct]).to be > 200
      expect(stats[:mitre_fallback]).to be > 0
    end

    it "produces source_id values matching the SecHub `<Service>.<N>` shape" do
      rows, _stats = described_class.from_paths(aws_direct_path: aws_path, mitre_path: mitre_path)
      bad = rows.reject { |r| r["source_id"].match?(/\A[A-Za-z][A-Za-z0-9]*\.\d+\z/) }
      expect(bad).to be_empty, "Non-SecHub-shaped source_ids: #{bad.first(5).map { |r| r['source_id'] }.inspect}"
    end

    it "produces lowercase target_id values matching OSCAL conventions" do
      rows, _stats = described_class.from_paths(aws_direct_path: aws_path, mitre_path: mitre_path)
      bad = rows.reject { |r| r["target_id"].match?(/\A[a-z]{2}-\d+(?:\.\d+)?(?:_smt\.[a-z])?\z/) }
      # Allow a tail percentage for fringe forms surfaced by parsing variations.
      expect(bad.length).to be < (rows.length * 0.05)
    end
  end
end
