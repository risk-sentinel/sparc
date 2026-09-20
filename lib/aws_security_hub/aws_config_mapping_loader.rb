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
    #
    # #1103 — `rev:` selects which revision's ids become the converter's
    # targets. It defaults to the revision the vendored document itself
    # declares, so the file and the converter cannot disagree; older vendored
    # files that predate `Rev` declare nothing and fall back to rev4, which is
    # what they actually held.
    #
    # This matters because the AWS Security Hub converter that chains through
    # this one is declared `target_rev: "5"`. While the vendored data was
    # rev4-only, that chain resolved rev4 statement-letter ids (`ac-2_smt.j`)
    # into a rev5 mapping, where they address nothing.
    def build(mitre_doc, rev: nil)
      selected = (rev || mitre_doc["rev"] || 4).to_i
      rows = []
      Array(mitre_doc["mappings"]).each do |entry|
        rule_name = entry["aws_config_rule_name"].to_s
        next if rule_name.empty?

        nist_ids = Array(nist_ids_for(entry, selected)).compact.uniq.reject(&:empty?)
        next if nist_ids.empty?

        rev4_raw = Array(entry["nist_rev4_raw"]).join(",")
        rev5_raw = Array(entry["nist_rev5_raw"]).join(",")

        remarks = "aws_config_rule_source_identifier=#{entry["aws_config_rule_source_identifier"]}"
        remarks += " | mitre_rev4=#{rev4_raw}" unless rev4_raw.empty?
        remarks += " | mitre_rev5=#{rev5_raw}" unless rev5_raw.empty?
        remarks += " | selected_rev=#{selected}"

        nist_ids.each do |nist_id|
          rows << {
            "source_id" => rule_name,
            "target_id" => nist_id,
            "relationship" => "intersects",
            "category" => "mitre_vendored",
            "remarks" => remarks
          }
        end
      end
      rows
    end

    # The ids for the requested revision, falling back to the flattened
    # `nist_oscal_ids` so a vendored file written before #1103 (which has no
    # per-revision keys at all) still loads instead of producing zero rows.
    def nist_ids_for(entry, rev)
      entry["nist_rev#{rev}_oscal_ids"].presence || entry["nist_oscal_ids"]
    end

    def from_path(path)
      build(JSON.parse(File.read(path)))
    end
  end
end
