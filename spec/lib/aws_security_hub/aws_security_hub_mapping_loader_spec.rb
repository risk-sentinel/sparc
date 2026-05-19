# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/aws_security_hub/aws_security_hub_mapping_loader")

RSpec.describe AwsSecurityHub::AwsSecurityHubMappingLoader do
  describe ".build" do
    it "emits one row per OSCAL NIST id (fanout)" do
      doc = {
        "mappings" => [
          {
            "sec_hub_id" => "IAM.3",
            "title" => "Rotate access keys",
            "aws_config_rule" => "access-keys-rotated",
            "nist_oscal_ids" => [ "ac-2.1", "ac-3.15" ]
          }
        ]
      }
      rows = described_class.build(doc)
      expect(rows.length).to eq(2)
      expect(rows.map { |r| r["target_id"] }).to contain_exactly("ac-2.1", "ac-3.15")
    end

    it "tags every row category=aws_direct and relationship=intersects" do
      doc = { "mappings" => [ { "sec_hub_id" => "IAM.3", "nist_oscal_ids" => [ "ac-3" ] } ] }
      rows = described_class.build(doc)
      expect(rows.first["category"]).to eq("aws_direct")
      expect(rows.first["relationship"]).to eq("intersects")
    end

    it "skips Sec Hub controls without an AWS-published NIST mapping" do
      # These are chained at import time via Config Rule, not seeded.
      doc = { "mappings" => [
        { "sec_hub_id" => "ACM.2", "aws_config_rule" => "acm-certificate-rsa-check", "nist_oscal_ids" => [] },
        { "sec_hub_id" => "Backup.2", "aws_config_rule" => nil, "nist_oscal_ids" => [] }
      ] }
      expect(described_class.build(doc)).to be_empty
    end

    it "stashes aws_config_rule + title + source in remarks" do
      doc = { "mappings" => [
        { "sec_hub_id" => "IAM.3", "title" => "Rotate", "aws_config_rule" => "access-keys-rotated",
          "nist_oscal_ids" => [ "ac-2.1" ] }
      ] }
      rows = described_class.build(doc)
      expect(rows.first["remarks"]).to include("title=Rotate")
      expect(rows.first["remarks"]).to include("aws_config_rule=access-keys-rotated")
      expect(rows.first["remarks"]).to include("source=aws_direct")
    end

    it "skips entries with empty sec_hub_id" do
      doc = { "mappings" => [ { "sec_hub_id" => "", "nist_oscal_ids" => [ "ac-3" ] } ] }
      expect(described_class.build(doc)).to eq([])
    end
  end

  describe ".build_config_rule_bridge" do
    it "returns a hash keyed by sec_hub_id with config rule names" do
      doc = { "mappings" => [
        { "sec_hub_id" => "IAM.3", "aws_config_rule" => "access-keys-rotated" },
        { "sec_hub_id" => "ACM.2", "aws_config_rule" => "acm-certificate-rsa-check" }
      ] }
      bridge = described_class.build_config_rule_bridge(doc)
      expect(bridge).to eq(
        "IAM.3" => "access-keys-rotated",
        "ACM.2" => "acm-certificate-rsa-check"
      )
    end

    it "maps Sec Hub controls without a Config rule to nil" do
      doc = { "mappings" => [ { "sec_hub_id" => "CloudTrail.6", "aws_config_rule" => nil } ] }
      bridge = described_class.build_config_rule_bridge(doc)
      expect(bridge["CloudTrail.6"]).to be_nil
    end
  end

  describe "real scraped data" do
    let(:doc) do
      path = Rails.root.join("lib/data_mappings/aws_security_hub_to_nist.json")
      JSON.parse(File.read(path))
    end

    it "produces an AWS-direct-only dataset (no MITRE pollution)" do
      rows = described_class.build(doc)
      expect(rows.map { |r| r["category"] }.uniq).to eq([ "aws_direct" ])
      expect(rows.length).to be > 2000
    end

    it "the config-rule bridge covers most Sec Hub controls" do
      bridge = described_class.build_config_rule_bridge(doc)
      total = doc["mappings"].length
      with_rule = bridge.values.compact.length
      expect(with_rule.to_f / total).to be > 0.9
    end
  end
end
