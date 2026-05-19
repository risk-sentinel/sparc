# frozen_string_literal: true

require "json"

# Issue #491 — Composes the final AWS Security Hub -> NIST 800-53 rev5
# mapping from two source files:
#
#   PRIMARY:
#     lib/data_mappings/aws_security_hub_to_nist.json
#       (Slice 2 -- scraped from AWS Security Hub User Guide; rev5)
#
#   FALLBACK:
#     lib/data_mappings/mitre_aws_config_to_nist.json
#       (Slice 1 -- vendored from mitre/heimdall2; rev4, joined via
#        aws_config_rule_name when AWS publishes no direct NIST mapping)
#
# Composition rules:
#   - For each SecHub control:
#     a. If the AWS-direct scrape has at least one nist_oscal_id, use
#        that set; mark source = "aws_direct".
#     b. Else if the SecHub control has an aws_config_rule and that rule
#        appears in the MITRE map, use MITRE's nist_oscal_ids; mark
#        source = "mitre_fallback".
#     c. Else: emit no rows; the control becomes a coverage gap (slice 5
#        coverage report will surface these).
#   - Many-to-many: one SecHub control may produce multiple rows (one per
#     NIST id) -- the database's unique-pair index prevents duplicates.
#
# This module is pure-function: it takes two parsed Hashes (or paths)
# and returns an Array<Hash> ready for ConverterEntry.insert_all. No
# database, no IO except the file readers.
module AwsSecurityHub
  module CompositeMappingBuilder
    module_function

    def from_paths(aws_direct_path:, mitre_path:)
      aws_doc   = JSON.parse(File.read(aws_direct_path))
      mitre_doc = JSON.parse(File.read(mitre_path))
      build(aws_direct: aws_doc, mitre: mitre_doc)
    end

    def build(aws_direct:, mitre:)
      mitre_index = build_mitre_index(mitre)

      rows = []
      stats = { aws_direct: 0, mitre_fallback: 0, unmapped: 0 }

      Array(aws_direct["mappings"]).each do |entry|
        sec_hub_id = entry["sec_hub_id"].to_s
        next if sec_hub_id.empty?

        nist_ids = Array(entry["nist_oscal_ids"]).compact.uniq.reject(&:empty?)
        source = "aws_direct"

        if nist_ids.empty?
          rule = entry["aws_config_rule"].to_s
          mitre_entry = mitre_index[rule] if !rule.empty?
          if mitre_entry
            nist_ids = Array(mitre_entry["nist_oscal_ids"]).compact.uniq.reject(&:empty?)
            source = "mitre_fallback"
          end
        end

        if nist_ids.empty?
          stats[:unmapped] += 1
          next
        end

        stats[source.to_sym] += 1

        nist_ids.each do |nist_id|
          rows << {
            "source_id" => sec_hub_id,
            "target_id" => nist_id,
            "relationship" => "intersects",
            "category" => source,
            "remarks" => build_remarks(entry, source: source, mitre_entry: source == "mitre_fallback" ? mitre_index[entry["aws_config_rule"].to_s] : nil)
          }
        end
      end

      [ rows, stats ]
    end

    def build_mitre_index(mitre_doc)
      idx = {}
      Array(mitre_doc["mappings"]).each do |row|
        rule = row["aws_config_rule_name"].to_s
        idx[rule] = row unless rule.empty?
      end
      idx
    end

    def build_remarks(aws_entry, source:, mitre_entry: nil)
      parts = []
      parts << "title=#{aws_entry["title"]}" if aws_entry["title"].to_s != ""
      if aws_entry["aws_config_rule"].to_s != ""
        parts << "aws_config_rule=#{aws_entry["aws_config_rule"]}"
      end
      parts << "source=#{source}"
      if source == "mitre_fallback" && mitre_entry
        rev4 = Array(mitre_entry["nist_rev4_raw"]).join(",")
        parts << "mitre_rev4=#{rev4}" unless rev4.empty?
      end
      parts.join(" | ")
    end
  end
end
