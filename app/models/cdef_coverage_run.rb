# frozen_string_literal: true

# #904 — a saved CDEF coverage analysis.
#
# Holds the derived census only. The Terraform that produced it was parsed in
# the request and discarded: no blob, no attachment, no attribute values. See
# the migration for why, and spec/requests for the assertion that keeps it true.
class CdefCoverageRun < ApplicationRecord
  belongs_to :authorization_boundary, optional: true
  belongs_to :created_by_user, class_name: "User", optional: true

  has_many :cdef_coverage_results, dependent: :destroy

  validates :analyzed_at, presence: true

  scope :recent, -> { order(analyzed_at: :desc) }

  # Persist a CdefCoverageAnalysis::Report.
  #
  # Separate from analysing on purpose: the wizard runs, shows its answer, and
  # only writes when an operator chooses to attach it to a boundary (#904).
  def self.persist!(report:, actor:, authorization_boundary: nil)
    counts = report.counts

    run = create!(
      authorization_boundary: authorization_boundary,
      created_by_user: actor,
      created_by: actor&.display_label.presence || actor&.email,
      analyzed_at: Time.current.utc,
      source_files: report.to_h[:sources],
      unmapped_resource_types: report.to_h[:unmapped_resource_types],
      adopt_count: counts["adopt"],
      keep_custom_count: counts["keep_custom"],
      needs_custom_count: counts["needs_custom"],
      stale_custom_count: counts["stale_custom"]
    )

    report.findings.each do |finding|
      run.cdef_coverage_results.create!(
        service_key: finding.service_key,
        verdict: finding.verdict,
        resource_count: finding.resource_count,
        resource_types: finding.resource_types,
        inferred: finding.inferred?,
        cdef_documents: finding.cdef_documents
      )
    end

    run
  end

  def counts
    { "adopt" => adopt_count, "keep_custom" => keep_custom_count,
      "needs_custom" => needs_custom_count, "stale_custom" => stale_custom_count }
  end

  # What the operator still has to do: author the missing CDEFs, review the
  # unused ones.
  def actionable_results
    cdef_coverage_results.where(verdict: %w[needs_custom stale_custom]).order(:verdict, :service_key)
  end
end
