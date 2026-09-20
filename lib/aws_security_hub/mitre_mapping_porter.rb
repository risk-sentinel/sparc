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
#     "rev": 5,
#     "available_revs": [4, 5],
#     "total_entries": <N>,
#     "mappings": [
#       {
#         "aws_config_rule_name": "iam-password-policy",
#         "aws_config_rule_source_identifier": "IAM_PASSWORD_POLICY",
#         "nist_rev4_raw": ["AC-2(1)", "AC-2(f)", ...],
#         "nist_rev4_oscal_ids": ["ac-2.1", "ac-2_smt.f", ...],
#         "nist_rev5_raw": ["AC-2(1)", ...],
#         "nist_rev5_oscal_ids": ["ac-2.1", ...],
#         "nist_oscal_ids": ["ac-2.1", ...]
#       },
#       ...
#     ]
#   }
#
# #1103 — `Rev`, and why `nist_oscal_ids` is now rev5.
#
# Upstream used to publish one row per rule. It now publishes one row per
# (rule, revision) and carries a `Rev` field, because "AwsConfigMapping keys its
# lookups by revision, so the two rows for a rule no longer overwrite each
# other". The vendored copy here was rev4-only, and every consumer of it —
# including the second hop of the AWS Security Hub -> NIST chain, whose
# converter is declared `target_rev: "5"` — was therefore resolving rev4
# control ids into a rev5 mapping. That is not a cosmetic mismatch: 22 distinct
# rev4 STATEMENT-letter forms (`ac-2_smt.j`, `au-12_smt.a`, `ca-7_smt.b`) were
# reaching rev5 consumers, and per upstream's own note rev4 statement letters
# "do not survive to Rev 5, which renumbered control statements" — so those ids
# address nothing in the rev5 catalog.
#
# Both revisions are kept: rev4 is the audit trail, and a rev4 consumer can
# still select it. `nist_oscal_ids` is the SELECTED revision (rev5) so existing
# consumers get the correct ids without each one having to know about `Rev`.
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
      # #1103 — LOCATE the declaration, do not assume it starts the file.
      # This was anchored with \A, and upstream now opens with a 20-line `//`
      # header explaining its own sourcing and precedence rules. The anchor
      # silently failed to match, leaving `export const data = [...]` in the
      # string, and the whole re-vendor died in JSON.parse on "export".
      marker = ts_text.index(/^export const data\s*=/)
      raise ParseError, "No `export const data =` declaration in MITRE TS source" if marker.nil?

      body = ts_text[marker..].sub(/\Aexport const data\s*=\s*/, "").sub(/;\s*\z/, "")

      # 0. Whole-line `//` comments. Only lines that BEGIN with the marker are
      #    dropped, so a value that happens to contain `//` survives.
      body = body.gsub(/^\s*\/\/.*$/, "")

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

    # The revision `nist_oscal_ids` carries, and the one the AWS Security Hub
    # chain resolves against. Rev 4 is retained per-rule alongside it.
    SELECTED_REV = 5
    AVAILABLE_REVS = [ 4, 5 ].freeze

    # Split one upstream row's `NIST-ID` into its individual control ids.
    # Upstream packs several into one field, pipe-joined: "AC-2(1)|AC-2(j)".
    def self.raw_ids_for(row)
      row.fetch("NIST-ID", "").split("|").map(&:strip).reject(&:empty?)
    end

    # The revision a row belongs to. Rows from the pre-#1103 upstream carried no
    # `Rev` at all and were rev4 by definition, so that is the fallback — an
    # absent `Rev` must never be silently promoted to rev5.
    def self.rev_for(row)
      row.fetch("Rev", 4).to_i
    end

    # Convert one MITRE row to a SPARC-shaped Hash with both the raw NIST
    # strings (audit trail) and the normalized OSCAL ids (consumer-ready).
    #
    # Kept for a single row so the parse remains individually testable; the
    # per-rule merge across revisions happens in `normalize_rows`.
    def self.normalize_row(row)
      raw_ids = raw_ids_for(row)
      rev     = rev_for(row)
      {
        "aws_config_rule_name" => row.fetch("AwsConfigRuleName"),
        "aws_config_rule_source_identifier" => row.fetch("AwsConfigRuleSourceIdentifier"),
        "rev" => rev,
        "nist_raw" => raw_ids,
        "nist_oscal_ids" => NistIdNormalizer.normalize_all(raw_ids)
      }
    end

    # Collapse the per-(rule, revision) upstream rows into one entry per rule
    # carrying every revision it publishes.
    #
    # Grouping by rule name rather than emitting a row per revision keeps
    # `aws_config_rule_name` UNIQUE in the output, which is what the converter
    # loader and the Security Hub bridge both key on. Emitting 788 rows with
    # duplicate names would have let a rev4 row silently overwrite its rev5
    # twin, revision by revision, exactly the collision upstream restructured
    # its own file to avoid.
    def self.normalize_rows(rows)
      rows.group_by { |row| row.fetch("AwsConfigRuleName") }.map do |rule_name, group|
        entry = {
          "aws_config_rule_name" => rule_name,
          "aws_config_rule_source_identifier" => group.first.fetch("AwsConfigRuleSourceIdentifier")
        }

        AVAILABLE_REVS.each do |rev|
          raw = group.select { |row| rev_for(row) == rev }.flat_map { |row| raw_ids_for(row) }.uniq
          entry["nist_rev#{rev}_raw"] = raw
          entry["nist_rev#{rev}_oscal_ids"] = NistIdNormalizer.normalize_all(raw)
        end

        # The selected revision, flattened for consumers that do not care about
        # revisions. Falls back to rev4 for a rule upstream maps only there —
        # better a rev4 id than no mapping, and `nist_rev4_raw` says which it is.
        entry["nist_oscal_ids"] =
          entry["nist_rev#{SELECTED_REV}_oscal_ids"].presence || entry["nist_rev4_oscal_ids"]

        entry
      end
    end

    # Build the full output document.
    def self.build_document(rows, source_url: UPSTREAM_TS_URL, vendored_at: Time.current.utc)
      mappings = normalize_rows(rows)
      {
        "format" => "mitre_aws_config_to_nist",
        "version" => "vendored-#{vendored_at.strftime('%Y-%m-%d')}",
        "source" => source_url,
        "license" => "Apache-2.0",
        "attribution" => "© 2025 The MITRE Corporation. Approved for Public Release; " \
                         "Distribution Unlimited. Case Number 18-3678.",
        "description" => "AWS Config Rule → NIST SP 800-53 mapping vendored from " \
                         "mitre/heimdall2, carrying both rev4 and rev5. Used by SPARC as " \
                         "the base layer of the AWS Security Hub → NIST converter " \
                         "(issues #491, #1103). `nist_oscal_ids` is rev#{SELECTED_REV}.",
        "rev" => SELECTED_REV,
        "available_revs" => AVAILABLE_REVS,
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
