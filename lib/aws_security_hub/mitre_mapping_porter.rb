# frozen_string_literal: true

require "json"
require Rails.root.join("lib/aws_security_hub/nist_id_normalizer")

# Issue #491 — One-shot porter that converts MITRE's TypeScript
# AwsConfigMappingData.ts into a SPARC-shaped JSON mapping file under
# lib/data_mappings/.
#
# Two consumption paths:
#   1. The rake task `mappings:vendor_mitre_aws_config` invokes this
#      against a freshly-downloaded copy of the upstream TS file -- used
#      when re-vendoring (MITRE adds entries).
#   2. The class methods are individually testable: parse_ts_source,
#      normalize_row, etc.
#
# Output schema (lib/data_mappings/mitre_aws_config_to_nist.json):
#   {
#     "format": "mitre_aws_config_to_nist",
#     "version": "<vendor-timestamp>",
#     "source": "<upstream TS URL>",
#     "license": "Apache-2.0",
#     "attribution": "© <year> The MITRE Corporation.",
#     "description": "...",
#     "rev": 4,
#     "total_entries": <N>,
#     "mappings": [
#       {
#         "aws_config_rule_name": "iam-password-policy",
#         "aws_config_rule_source_identifier": "IAM_PASSWORD_POLICY",
#         "nist_rev4_raw": ["AC-2(1)", "AC-2(f)", ...],
#         "nist_oscal_ids": ["ac-2.1", "ac-2_smt.f", ...]
#       },
#       ...
#     ]
#   }
module AwsSecurityHub
  class MitreMappingPorter
    UPSTREAM_TS_URL =
      "https://raw.githubusercontent.com/mitre/heimdall2/master/" \
      "libs/hdf-converters/src/mappings/AwsConfigMappingData.ts"

    class ParseError < StandardError; end

    # Convert MITRE's TS array literal into a Ruby Array of Hashes.
    # The source file is hand-formatted but consistent: bare-identifier
    # keys, single-quoted string values, no escaped quotes inside strings.
    def self.parse_ts_source(ts_text)
      body = ts_text.sub(/\Aexport const data =\s*/, "").sub(/;\s*\z/, "")

      # 1. Bare-identifier keys (Foo:) -> JSON quoted keys ("Foo":).
      body = body.gsub(/^(\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:/, '\1"\2":')

      # 2. Single-quoted strings -> double-quoted.
      body = body.gsub(/'([^']*)'/, '"\1"')

      # 3. TS allows trailing commas; JSON does not.
      body = body.gsub(/,(\s*[}\]])/, '\1')

      JSON.parse(body)
    rescue JSON::ParserError => e
      raise ParseError, "Failed to parse MITRE TS source: #{e.message}"
    end

    # Convert one MITRE row to a SPARC-shaped Hash with both the raw NIST
    # strings (audit trail) and the normalized OSCAL ids (consumer-ready).
    def self.normalize_row(row)
      raw_ids = row.fetch("NIST-ID", "").split("|").map(&:strip).reject(&:empty?)
      {
        "aws_config_rule_name" => row.fetch("AwsConfigRuleName"),
        "aws_config_rule_source_identifier" => row.fetch("AwsConfigRuleSourceIdentifier"),
        "nist_rev4_raw" => raw_ids,
        "nist_oscal_ids" => NistIdNormalizer.normalize_all(raw_ids)
      }
    end

    # Build the full output document.
    def self.build_document(rows, source_url: UPSTREAM_TS_URL, vendored_at: Time.current.utc)
      mappings = rows.map { |row| normalize_row(row) }
      {
        "format" => "mitre_aws_config_to_nist",
        "version" => "vendored-#{vendored_at.strftime('%Y-%m-%d')}",
        "source" => source_url,
        "license" => "Apache-2.0",
        "attribution" => "© 2025 The MITRE Corporation. Approved for Public Release; " \
                         "Distribution Unlimited. Case Number 18-3678.",
        "description" => "AWS Config Rule → NIST SP 800-53 rev4 mapping vendored from " \
                         "mitre/heimdall2. Used by SPARC as the base layer of the " \
                         "AWS Security Hub → NIST converter (issue #491).",
        "rev" => 4,
        "total_entries" => mappings.length,
        "mappings" => mappings
      }
    end

    def self.write!(rows, path:)
      doc = build_document(rows)
      File.write(path, JSON.pretty_generate(doc) + "\n")
      doc
    end
  end
end
