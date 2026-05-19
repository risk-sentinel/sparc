# frozen_string_literal: true

require "json"

# Issue #494 -- Builds ConverterEntry rows for the
# `aws_security_hub_to_nist` Converter from the scraped AWS Security
# Hub user-guide data (lib/data_mappings/aws_security_hub_to_nist.json).
#
# Only AWS-direct mappings are loaded here. Sec Hub controls without
# an AWS-published NIST mapping are NOT inserted -- the chain via AWS
# Config Rule happens at import time inside AwsLabsCdefImportService,
# which preserves the source provenance and lets operators hand-edit
# either layer independently.
#
# remarks captures the aws_config_rule so the chain logic can pull it
# without needing a separate bridge table.
module AwsSecurityHub
  module AwsSecurityHubMappingLoader
    module_function

    # Takes a parsed aws_security_hub_to_nist.json doc. Returns an
    # Array<Hash> of rows ready for ConverterEntry.insert_all.
    # Each scraped entry produces one row per OSCAL NIST id (fanout).
    # Entries with no nist_oscal_ids are skipped (chained at import time).
    def build(aws_doc)
      rows = []
      Array(aws_doc["mappings"]).each do |entry|
        sec_hub_id = entry["sec_hub_id"].to_s
        next if sec_hub_id.empty?

        nist_ids = Array(entry["nist_oscal_ids"]).compact.uniq.reject(&:empty?)
        next if nist_ids.empty?

        config_rule = entry["aws_config_rule"].to_s
        title = entry["title"].to_s
        remarks_parts = []
        remarks_parts << "title=#{title}" unless title.empty?
        remarks_parts << "aws_config_rule=#{config_rule}" unless config_rule.empty?
        remarks_parts << "source=aws_direct"

        nist_ids.each do |nist_id|
          rows << {
            "source_id" => sec_hub_id,
            "target_id" => nist_id,
            "relationship" => "intersects",
            "category" => "aws_direct",
            "remarks" => remarks_parts.join(" | ")
          }
        end
      end
      rows
    end

    def from_path(path)
      build(JSON.parse(File.read(path)))
    end

    # Build the SecHub -> AWS Config Rule bridge for runtime chain
    # use. Keyed by sec_hub_id, value is the config rule name (or nil
    # for check-based controls).
    def build_config_rule_bridge(aws_doc)
      bridge = {}
      Array(aws_doc["mappings"]).each do |entry|
        sec_hub_id = entry["sec_hub_id"].to_s
        rule = entry["aws_config_rule"].to_s
        next if sec_hub_id.empty?

        bridge[sec_hub_id] = rule.empty? ? nil : rule
      end
      bridge
    end
  end
end
