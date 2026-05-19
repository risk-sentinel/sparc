# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/aws_security_hub/aws_config_mapping_loader")

RSpec.describe AwsSecurityHub::AwsConfigMappingLoader do
  describe ".build" do
    it "emits one row per OSCAL NIST id (fanout)" do
      doc = {
        "mappings" => [
          {
            "aws_config_rule_name" => "iam-password-policy",
            "aws_config_rule_source_identifier" => "IAM_PASSWORD_POLICY",
            "nist_rev4_raw" => [ "AC-2(1)", "IA-2" ],
            "nist_oscal_ids" => [ "ac-2.1", "ia-2" ]
          }
        ]
      }

      rows = described_class.build(doc)
      expect(rows.length).to eq(2)
      expect(rows.map { |r| r["target_id"] }).to contain_exactly("ac-2.1", "ia-2")
      expect(rows.map { |r| r["source_id"] }.uniq).to eq([ "iam-password-policy" ])
    end

    it "tags every row category=mitre_vendored and relationship=intersects" do
      doc = {
        "mappings" => [
          { "aws_config_rule_name" => "foo", "aws_config_rule_source_identifier" => "FOO", "nist_oscal_ids" => [ "ac-3" ] }
        ]
      }
      rows = described_class.build(doc)
      expect(rows.first["category"]).to eq("mitre_vendored")
      expect(rows.first["relationship"]).to eq("intersects")
    end

    it "stashes rev4 raw ids in remarks for audit" do
      doc = {
        "mappings" => [
          { "aws_config_rule_name" => "foo", "aws_config_rule_source_identifier" => "FOO",
            "nist_rev4_raw" => [ "AC-2(1)" ], "nist_oscal_ids" => [ "ac-2.1" ] }
        ]
      }
      rows = described_class.build(doc)
      expect(rows.first["remarks"]).to include("mitre_rev4=AC-2(1)")
      expect(rows.first["remarks"]).to include("aws_config_rule_source_identifier=FOO")
    end

    it "skips entries with empty rule name" do
      doc = { "mappings" => [ { "aws_config_rule_name" => "", "nist_oscal_ids" => [ "ac-3" ] } ] }
      expect(described_class.build(doc)).to eq([])
    end

    it "skips entries with no normalized NIST ids" do
      doc = { "mappings" => [ { "aws_config_rule_name" => "foo", "nist_oscal_ids" => [] } ] }
      expect(described_class.build(doc)).to eq([])
    end
  end

  describe "real vendored data" do
    let(:doc) do
      path = Rails.root.join("lib/data_mappings/mitre_aws_config_to_nist.json")
      JSON.parse(File.read(path))
    end

    it "produces a viable converter dataset" do
      rows = described_class.build(doc)
      expect(rows.length).to be > 300
      pairs = rows.map { |r| [ r["source_id"], r["target_id"] ] }
      expect(pairs.length).to eq(pairs.uniq.length), "Duplicates would violate the unique-pair index"
    end
  end
end
