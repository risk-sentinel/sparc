# frozen_string_literal: true

# Issue #491 / #494 / #1103 -- Two-hop NIST enrichment for CDEF controls.
#
# #1103 — this logic used to be private to AwsLabsCdefImportService, so it ran
# ONLY on the weekly AWS Labs refresh. A CDEF uploaded through the UI went
# DocumentConversionJob -> CdefJsonParserService#parse and stopped there, which
# left every AWS control carrying its Security Hub identifier and no NIST
# reference at all: the controls existed, but they belonged to no NIST family,
# so the heat map drew nothing and the Security Hub -> NIST converter had
# nothing to map. That is the reported defect. The logic is unchanged; it now
# lives where BOTH entry points can reach it.
#
# For each AWS Security Hub control_id on a freshly-parsed CdefControl:
#
#   1. Direct lookup in the aws_security_hub_to_nist Converter
#      (sourced from AWS Security Hub User Guide).
#      Found  -> use those NIST ids; mark source = "aws_direct".
#      Empty  -> proceed to step 2.
#
#   2. Pull the aws_config_rule for this SecHub id from the
#      lib/data_mappings/aws_security_hub_to_nist.json bridge file
#      (cached in memory).
#      None recorded -> leave unmapped.
#
#   3. Lookup that Config Rule in the aws_config_to_nist Converter
#      (sourced from mitre/heimdall2, hand-extensible).
#      Found  -> use those NIST ids; mark source = "via_config_rule".
#      Empty  -> leave unmapped.
#
# #912 — the AWS upstream identifier is never lost, but it no longer lives in
# `control_id`. It moves to `source_control_id` (verbatim, never rewritten)
# and `control_id` carries the NIST reference the converter resolved, or NULL
# where it resolved nothing. Before the split both meanings shared one column,
# so a Security Hub id was indistinguishable from a NIST control at every
# consumer — and canonicalisation had to be disabled on the whole model to
# avoid rewriting `IAM.3` to `iam.3`.
#
# The enrichment FIELDS below are unchanged: they remain the audit trail of
# how the mapping was derived.
#
# Fields written per enriched CdefControl:
#   - aws_security_hub_id   : the original SecHub identifier
#   - nist_oscal_ids        : comma-joined OSCAL ids (sorted)
#   - nist_primary_id       : lowest-sorted NIST id (grouping key)
#   - nist_mapping_source   : "aws_direct" | "via_config_rule"
#   - aws_config_rule       : the Config Rule name (when via_config_rule)
#
# NIST controls: CM-6 (configuration settings are derived from an authoritative
# mapping, not hand-entered), SA-4(9) (the provenance of each mapping is
# recorded alongside it).
class CdefNistEnrichmentService
  include CciNistResolvable

  # A Security Hub control identifier: "IAM.3", "EC2.15", "NetworkFirewall.10".
  # Anything else on a CDEF control is already a NIST id (AWS Labs publishes a
  # MIXED corpus — see spec/fixtures/files/components/aws_labs) or belongs to
  # another vocabulary entirely, and must be left exactly as it is.
  SEC_HUB_ID_PATTERN = /\A[A-Za-z][A-Za-z0-9]*\.\d+\z/

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  # Enrich every AWS Security Hub control on `document`. Returns the number of
  # controls that received a NIST mapping. Safe to re-run: `record_aws_source!`
  # and `upsert_cdef_field!` are both idempotent, so a document that is
  # re-imported or re-enriched converges rather than duplicating fields.
  def enrich!(document)
    sec_hub_converter    = Converter.find_by(converter_type: "aws_security_hub_to_nist")
    aws_config_converter = Converter.find_by(converter_type: "aws_config_to_nist")

    unless sec_hub_converter
      @logger.debug("[CdefNistEnrichmentService] No aws_security_hub_to_nist Converter; skipping NIST enrichment")
      return 0
    end

    bridge = sec_hub_config_rule_bridge

    enriched_count = 0
    document.cdef_controls.find_each do |control|
      # #912 — the Security Hub id is the SOURCE identifier. Read it from
      # `source_control_id` where the split has already been applied, and fall
      # back to `control_id` for rows the deferred backfill has not reached yet.
      sec_hub_id = control.source_identifier.to_s.presence || control.control_id.to_s
      next unless sec_hub_id.match?(SEC_HUB_ID_PATTERN)

      # #912 — clear the Security Hub id out of `control_id` before attempting
      # resolution. If the converter maps it, `write_enrichment!` writes the NIST
      # reference back; if it does not, the row is correctly left with no control
      # identifier and is reported as unmapped rather than presenting a Security
      # Hub id as though it were a NIST control.
      record_aws_source!(control, sec_hub_id)
      # Compare canonically: `control_id` is canonicalised on write now, so the
      # stored value is `iam.99999` while the source is `IAM.99999`. Comparing
      # raw never matched, and the Security Hub id stayed in the NIST column.
      if control.control_id.present? && control.control_id == ControlId.canonical(sec_hub_id)
        # The family went with it. An unresolved rule has no NIST family, and
        # leaving the Security Hub id there put unmapped rules on the heatmap as
        # though they were a control family. `source_control_id` keeps the rule.
        control.update_columns(control_id: nil, control_family: nil)
      end

      direct_ids = sec_hub_converter.converter_entries
        .where(source_id: sec_hub_id)
        .reorder(nil).distinct.pluck(:target_id).uniq.sort

      if direct_ids.any?
        write_enrichment!(control, sec_hub_id, direct_ids, source: "aws_direct")
        enriched_count += 1
        next
      end

      # Fallback: chain through AWS Config Rule.
      config_rule = bridge[sec_hub_id]
      next if config_rule.nil? || config_rule.empty? || aws_config_converter.nil?

      chained_ids = aws_config_converter.converter_entries
        .where(source_id: config_rule)
        .reorder(nil).distinct.pluck(:target_id).uniq.sort

      next if chained_ids.empty?

      write_enrichment!(control, sec_hub_id, chained_ids, source: "via_config_rule", config_rule: config_rule)
      enriched_count += 1
    end

    if enriched_count > 0
      @logger.info("[CdefNistEnrichmentService] Enriched #{enriched_count} controls with NIST mappings " \
                   "for document #{document.id} (#{document.name})")
    end

    enriched_count
  end

  private

  # Provenance first, for every AWS control — mapped or not. An unmapped
  # Security Hub control must still say where it came from.
  def record_aws_source!(control, sec_hub_id)
    return if control.source_control_id == sec_hub_id && control.source_vocabulary == "aws_security_hub"

    control.update_columns(source_control_id: sec_hub_id, source_vocabulary: "aws_security_hub")
  end

  def write_enrichment!(control, sec_hub_id, nist_ids, source:, config_rule: nil)
    # #912 — `control_id` now holds the NIST reference. `update_columns` skips
    # validations deliberately: a control invalid for an unrelated reason must
    # still receive its resolved mapping.
    #
    # `control_family` MUST move with it. It is set at parse time from whatever
    # `implemented-requirements[].control-id` held, which for an AWS CDEF is the
    # Security Hub rule — so enriching `control_id` to `ca-7` while the family
    # stayed "ELASTICBEANSTALK.1" left the two columns describing different
    # vocabularies. The heatmap groups by family, so it drew one card per AWS
    # RULE instead of one per NIST family, with a label no card could contain.
    control.update_columns(
      control_id:     ControlId.canonical(nist_ids.first),
      control_family: nist_family_from_id(nist_ids.first)
    )

    upsert_cdef_field!(control, "aws_security_hub_id", sec_hub_id, editable: false)
    upsert_cdef_field!(control, "nist_oscal_ids", nist_ids.join(","), editable: false)
    upsert_cdef_field!(control, "nist_primary_id", nist_ids.first, editable: false)
    upsert_cdef_field!(control, "nist_mapping_source", source, editable: false)
    upsert_cdef_field!(control, "aws_config_rule", config_rule, editable: false) if config_rule
  end

  def upsert_cdef_field!(control, field_name, field_value, editable:)
    field = control.cdef_control_fields.find_or_initialize_by(field_name: field_name)
    field.update!(field_value: field_value, editable: editable)
  end

  # Cached SecHub -> AWS Config Rule bridge, built once per service
  # instance from the scraped JSON. Used as the second hop when the
  # AWS Security Hub converter has no direct row for a SecHub id.
  def sec_hub_config_rule_bridge
    @sec_hub_config_rule_bridge ||= begin
      require Rails.root.join("lib/aws_security_hub/aws_security_hub_mapping_loader")
      path = Rails.root.join("lib/data_mappings/aws_security_hub_to_nist.json")
      if path.exist?
        AwsSecurityHub::AwsSecurityHubMappingLoader.build_config_rule_bridge(JSON.parse(File.read(path)))
      else
        {}
      end
    end
  end
end
