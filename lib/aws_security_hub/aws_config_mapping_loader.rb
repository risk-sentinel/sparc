# frozen_string_literal: true

require "json"

# Issue #494 -- Builds ConverterEntry rows for the
# `aws_config_to_nist` Converter from the vendored MITRE data
# (lib/data_mappings/mitre_aws_config_to_nist.json).
#
# Decoupled from AWS Security Hub: this converter is also useful for
# Steampipe / Prowler / Audit Manager / Conformance Pack tooling that
# references AWS Config Rule names. Hand-edits via the converter UI
# persist; the next MITRE re-vendor only adds/changes rows for the
# source identifiers MITRE knows about, leaving operator-added rows
# alone (unique-pair index dedupes naturally).
module AwsSecurityHub
  module AwsConfigMappingLoader
    module_function

    # Takes a parsed mitre_aws_config_to_nist.json doc. Returns an
    # Array<Hash> of rows ready for ConverterEntry.insert_all.
    # Each MITRE row produces one row per OSCAL NIST id (fanout).
    def build(mitre_doc)
      rows = []
      Array(mitre_doc["mappings"]).each do |entry|
        rule_name = entry["aws_config_rule_name"].to_s
        next if rule_name.empty?

        nist_ids = Array(entry["nist_oscal_ids"]).compact.uniq.reject(&:empty?)
        next if nist_ids.empty?

        rev4_raw = Array(entry["nist_rev4_raw"]).join(",")

        nist_ids.each do |nist_id|
          rows << {
            "source_id" => rule_name,
            "target_id" => nist_id,
            "relationship" => "intersects",
            "category" => "mitre_vendored",
            "remarks" => "aws_config_rule_source_identifier=#{entry["aws_config_rule_source_identifier"]} | mitre_rev4=#{rev4_raw}"
          }
        end
      end
      rows
    end

    def from_path(path)
      build(JSON.parse(File.read(path)))
    end
  end
end
