# frozen_string_literal: true

# #904 — one service's verdict within a saved coverage run.
#
# `resource_types` holds Terraform type names (`aws_db_instance`), never
# resource values. `inferred` marks a service key derived from a resource type's
# naming rather than matched by a mapping rule, so a reader is never left
# guessing whether SPARC actually recognises the service.
class CdefCoverageResult < ApplicationRecord
  belongs_to :cdef_coverage_run

  VERDICTS = CdefCoverageAnalysis::VERDICTS

  VERDICT_LABELS = {
    "adopt" => "Adopt AWS Labs CDEF",
    "keep_custom" => "Keep custom CDEF",
    "needs_custom" => "Needs a CDEF",
    "stale_custom" => "Unused CDEF"
  }.freeze

  validates :service_key, presence: true
  validates :verdict, presence: true, inclusion: { in: VERDICTS }

  scope :needing_authoring, -> { where(verdict: "needs_custom") }
  scope :stale, -> { where(verdict: "stale_custom") }

  def verdict_label = VERDICT_LABELS.fetch(verdict, verdict.to_s.titleize)
end
