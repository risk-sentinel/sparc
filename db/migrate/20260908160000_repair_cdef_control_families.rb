# frozen_string_literal: true

# #1088 follow-up from the CDEF screen review — "The controls are not staying
# inside the cards (severity by control family)".
#
# Measured on the seeded AWS Elastic Beanstalk CDEF:
#
#   control_id=nil     control_family="ELASTICBEANSTALK.3"
#   control_id="ca-7"  control_family="ELASTICBEANSTALK.1"
#   control_id="si-2"  control_family="ELASTICBEANSTALK.2"
#
# `control_family` is written at PARSE time from whatever
# `implemented-requirements[].control-id` held — for an AWS CDEF, the Security
# Hub rule. `AwsLabsCdefImportService#write_enrichment!` then resolved that rule
# to a NIST control and rewrote `control_id`, but left the family alone, so the
# two columns ended up describing different vocabularies.
#
# The heatmap groups by family, so it drew one card per AWS RULE rather than one
# per NIST family, labelled with a string no 148px grid cell can hold — which is
# what the owner saw escaping the cards.
#
# ── The invariant ──────────────────────────────────────────────────────────
#
# Every parser already agrees on it:
#
#   cdef_json_parser_service.rb:115   split("-").first.upcase
#   cdef_json_parser_service.rb:310   nist_family_from_id(nist_id)
#   cdef_json_parser_service.rb:377   nist_family_from_id(nist_id)
#   cdef_xccdf_parser_service.rb:252  nist_family_from_id(nist_id)
#
#     control_family == nist_family_from_id(control_id)
#
# So this repairs the invariant rather than special-casing AWS: any importer
# that drifts from it is corrected the same way, and a row with no resolved
# control has no family to claim.
#
# Non-destructive. Only `control_family` is written; `source_control_id` keeps
# the Security Hub rule, which is the provenance the family column was wrongly
# carrying.
class RepairCdefControlFamilies < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      repaired = 0
      cleared  = 0

      CdefControl.find_each(batch_size: 500) do |control|
        expected = control.control_id.presence &&
                   control.control_id.to_s.split("-").first.upcase.presence
        next if control.control_family == expected

        control.update_columns(control_family: expected)
        expected.nil? ? cleared += 1 : repaired += 1
      end

      say "control_family: #{repaired} re-derived from the NIST id, #{cleared} cleared on unmapped rows"
    end
  end

  # Deliberately empty. The prior values were the wrong vocabulary in the wrong
  # column, and the Security Hub rule they held is still on `source_control_id`
  # — there is nothing worth restoring.
  def down; end
end
