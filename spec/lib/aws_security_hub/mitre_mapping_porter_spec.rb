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

    # #1103 — the real re-vendor failure. Upstream now opens with a header
    # comment block explaining its own sourcing rules; the \A-anchored strip
    # silently did not match and JSON.parse died on "export".
    it "parses a file that opens with a leading // comment header" do
      ts = <<~TS
        // AWS Config managed rule to NIST SP 800-53 mappings.
        //
        // Sources, in precedence order; a row's controls come from exactly one:
        //   1. AWS Config "Operational Best Practices for NIST 800-53"
        export const data = [
          {
            AwsConfigRuleSourceIdentifier: 'FOO_RULE',
            AwsConfigRuleName: 'foo-rule',
            'NIST-ID': 'AC-3',
            Rev: 5
          }
        ];
      TS

      rows = described_class.parse_ts_source(ts)

      expect(rows.length).to eq(1)
      expect(rows.first).to include("AwsConfigRuleName" => "foo-rule", "Rev" => 5)
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
      expect(result["rev"]).to eq(4)
      expect(result["nist_raw"]).to eq([ "AC-2(1)", "AC-2(f)", "IA-2" ])
      expect(result["nist_oscal_ids"]).to eq([ "ac-2.1", "ac-2_smt.f", "ia-2" ])
    end

    # An upstream row that predates the `Rev` field is rev4 by definition.
    # Defaulting the other way would silently promote rev4 statement-letter
    # ids into rev5, which is the bug #1103 exists to stop.
    it "treats a row with no Rev as rev4 rather than assuming the selected rev" do
      result = described_class.normalize_row(
        "AwsConfigRuleSourceIdentifier" => "FOO", "AwsConfigRuleName" => "foo", "NIST-ID" => "AC-3"
      )

      expect(result["rev"]).to eq(4)
    end

    it "handles single-entry NIST-ID (no pipes)" do
      row = {
        "AwsConfigRuleSourceIdentifier" => "FOO",
        "AwsConfigRuleName" => "foo",
        "NIST-ID" => "AC-3",
        "Rev" => 4
      }
      result = described_class.normalize_row(row)
      expect(result["nist_raw"]).to eq([ "AC-3" ])
      expect(result["nist_oscal_ids"]).to eq([ "ac-3" ])
    end
  end

  # #1103 — upstream publishes one row per (rule, revision). These collapse to
  # one entry per rule carrying every revision, so the rule name stays unique.
  describe ".normalize_rows" do
    def row(name, nist, rev)
      {
        "AwsConfigRuleSourceIdentifier" => name.tr("-", "_").upcase,
        "AwsConfigRuleName" => name, "NIST-ID" => nist, "Rev" => rev
      }
    end

    it "merges a rule's two revisions into one entry keyed by rule name" do
      result = described_class.normalize_rows([
        row("access-keys-rotated", "AC-3(15)", 5),
        row("access-keys-rotated", "AC-2(1)|AC-2(j)", 4)
      ])

      expect(result.length).to eq(1)
      entry = result.first
      expect(entry["aws_config_rule_name"]).to eq("access-keys-rotated")
      expect(entry["nist_rev5_oscal_ids"]).to eq([ "ac-3.15" ])
      expect(entry["nist_rev4_oscal_ids"]).to eq([ "ac-2.1", "ac-2_smt.j" ])
    end

    it "selects rev5 for nist_oscal_ids, leaving rev4 as the audit trail" do
      entry = described_class.normalize_rows([
        row("access-keys-rotated", "AC-3(15)", 5),
        row("access-keys-rotated", "AC-2(1)|AC-2(j)", 4)
      ]).first

      expect(entry["nist_oscal_ids"]).to eq([ "ac-3.15" ])
      # The rev4 statement-letter form is KEPT, but must not be what consumers
      # of `nist_oscal_ids` receive — it addresses nothing in the rev5 catalog.
      expect(entry["nist_rev4_oscal_ids"]).to include("ac-2_smt.j")
      expect(entry["nist_oscal_ids"]).not_to include("ac-2_smt.j")
    end

    it "falls back to rev4 for a rule upstream maps only there" do
      entry = described_class.normalize_rows([ row("rev4-only", "AC-3", 4) ]).first

      expect(entry["nist_rev5_oscal_ids"]).to be_empty
      expect(entry["nist_oscal_ids"]).to eq([ "ac-3" ])
    end

    it "keeps rule names unique so a revision cannot overwrite its twin" do
      result = described_class.normalize_rows([
        row("a", "AC-3", 5), row("a", "AC-3", 4),
        row("b", "SC-7", 5), row("b", "SC-7", 4)
      ])

      names = result.map { |e| e["aws_config_rule_name"] }
      expect(names).to eq(names.uniq)
      expect(names).to contain_exactly("a", "b")
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
      expect(doc["rev"]).to eq(5)
      expect(doc["available_revs"]).to eq([ 4, 5 ])
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

    # #1103 — the vendored file is the artifact that ships, so assert on IT,
    # not only on the porter that produced it.
    it "declares rev5 and carries both revisions" do
      expect(doc["rev"]).to eq(5)
      expect(doc["available_revs"]).to eq([ 4, 5 ])
    end

    it "has a unique rule name per entry" do
      names = doc["mappings"].map { |m| m["aws_config_rule_name"] }
      expect(names).to eq(names.uniq)
    end

    # The defect in one assertion: rev4 statement-letter ids must not reach a
    # consumer of `nist_oscal_ids`, because the rev5 catalog renumbered
    # statements and these address nothing there.
    it "ships no rev4 statement-letter ids in the selected revision" do
      selected = doc["mappings"].flat_map { |m| m["nist_oscal_ids"] }
      rev4     = doc["mappings"].flat_map { |m| m["nist_rev4_oscal_ids"] }

      expect(selected).to all(satisfy { |id| !id.include?("_smt.") })
      # ...while the rev4 audit trail still has them, so this is a SELECTION,
      # not a silent deletion of upstream data.
      expect(rev4.any? { |id| id.include?("_smt.") }).to be(true)
    end
  end
end
