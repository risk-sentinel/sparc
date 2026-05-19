# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/aws_security_hub/mitre_mapping_porter")

RSpec.describe AwsSecurityHub::MitreMappingPorter do
  describe ".parse_ts_source" do
    it "parses a minimal MITRE-shaped TS array" do
      ts = <<~TS
        export const data = [
          {
            AwsConfigRuleSourceIdentifier: 'FOO_RULE',
            AwsConfigRuleName: 'foo-rule',
            'NIST-ID': 'AC-3|AC-6',
            Rev: 4
          },
          {
            AwsConfigRuleSourceIdentifier: 'BAR_RULE',
            AwsConfigRuleName: 'bar-rule',
            'NIST-ID': 'IA-5(1)(a)',
            Rev: 4
          }
        ];
      TS

      rows = described_class.parse_ts_source(ts)

      expect(rows.length).to eq(2)
      expect(rows.first).to include(
        "AwsConfigRuleSourceIdentifier" => "FOO_RULE",
        "AwsConfigRuleName" => "foo-rule",
        "NIST-ID" => "AC-3|AC-6",
        "Rev" => 4
      )
    end

    it "tolerates trailing commas (TS-permitted, JSON-forbidden)" do
      ts = <<~TS
        export const data = [
          {
            AwsConfigRuleSourceIdentifier: 'FOO',
            AwsConfigRuleName: 'foo',
            'NIST-ID': 'AC-3',
            Rev: 4,
          },
        ];
      TS

      expect { described_class.parse_ts_source(ts) }.not_to raise_error
    end

    it "raises a typed ParseError on broken input" do
      expect {
        described_class.parse_ts_source("not valid ts at all")
      }.to raise_error(described_class::ParseError)
    end
  end

  describe ".normalize_row" do
    it "splits pipe-delimited NIST-ID and produces normalized OSCAL ids" do
      row = {
        "AwsConfigRuleSourceIdentifier" => "IAM_PASSWORD_POLICY",
        "AwsConfigRuleName" => "iam-password-policy",
        "NIST-ID" => "AC-2(1)|AC-2(f)|IA-2",
        "Rev" => 4
      }

      result = described_class.normalize_row(row)

      expect(result["aws_config_rule_name"]).to eq("iam-password-policy")
      expect(result["aws_config_rule_source_identifier"]).to eq("IAM_PASSWORD_POLICY")
      expect(result["nist_rev4_raw"]).to eq([ "AC-2(1)", "AC-2(f)", "IA-2" ])
      expect(result["nist_oscal_ids"]).to eq([ "ac-2.1", "ac-2_smt.f", "ia-2" ])
    end

    it "handles single-entry NIST-ID (no pipes)" do
      row = {
        "AwsConfigRuleSourceIdentifier" => "FOO",
        "AwsConfigRuleName" => "foo",
        "NIST-ID" => "AC-3",
        "Rev" => 4
      }
      result = described_class.normalize_row(row)
      expect(result["nist_rev4_raw"]).to eq([ "AC-3" ])
      expect(result["nist_oscal_ids"]).to eq([ "ac-3" ])
    end
  end

  describe ".build_document" do
    let(:rows) do
      [
        {
          "AwsConfigRuleSourceIdentifier" => "FOO",
          "AwsConfigRuleName" => "foo",
          "NIST-ID" => "AC-3",
          "Rev" => 4
        }
      ]
    end

    it "wraps mappings in SPARC envelope with attribution and source url" do
      doc = described_class.build_document(rows, vendored_at: Time.utc(2026, 5, 19))

      expect(doc["format"]).to eq("mitre_aws_config_to_nist")
      expect(doc["version"]).to eq("vendored-2026-05-19")
      expect(doc["license"]).to eq("Apache-2.0")
      expect(doc["attribution"]).to match(/MITRE/i)
      expect(doc["source"]).to match(%r{mitre/heimdall2})
      expect(doc["rev"]).to eq(4)
      expect(doc["total_entries"]).to eq(1)
      expect(doc["mappings"]).to be_an(Array).and have_attributes(length: 1)
    end
  end

  describe "vendored data file integrity" do
    let(:doc) do
      path = Rails.root.join("lib/data_mappings/mitre_aws_config_to_nist.json")
      JSON.parse(File.read(path))
    end

    it "is present, parseable, and Apache-2.0-attributed" do
      expect(doc["license"]).to eq("Apache-2.0")
      expect(doc["attribution"]).to include("MITRE")
      expect(doc["source"]).to include("mitre/heimdall2")
    end

    it "has at least 100 mappings" do
      expect(doc["total_entries"]).to be >= 100
      expect(doc["mappings"].length).to eq(doc["total_entries"])
    end

    it "every mapping carries both raw and normalized NIST ids" do
      sample = doc["mappings"].sample(10)
      sample.each do |m|
        expect(m["nist_rev4_raw"]).to be_an(Array).and(satisfy { |a| a.any? })
        expect(m["nist_oscal_ids"]).to be_an(Array)
      end
    end
  end
end
