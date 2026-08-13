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
    persist_report_hash!(hash: report.to_h, actor: actor, authorization_boundary: authorization_boundary)
  end

  # Persist from the report's serialised form.
  #
  # The save path goes through here rather than through a live Report because
  # the UI carries an analysis between two requests as a signed token — the
  # upload has been discarded by then, so re-deriving would mean re-uploading.
  # The hash is the same data either way; CdefCoverageReportToken is what makes
  # a round-tripped one trustworthy.
  def self.persist_report_hash!(hash:, actor:, authorization_boundary: nil)
    hash = hash.with_indifferent_access
    counts = hash[:counts] || {}

    run = create!(
      authorization_boundary: authorization_boundary,
      created_by_user: actor,
      created_by: actor&.display_label.presence || actor&.email,
      analyzed_at: Time.current.utc,
      source_files: Array(hash[:sources]),
      unmapped_resource_types: Array(hash[:unmapped_resource_types]),
      adopt_count: counts["adopt"].to_i,
      keep_custom_count: counts["keep_custom"].to_i,
      needs_custom_count: counts["needs_custom"].to_i,
      stale_custom_count: counts["stale_custom"].to_i
    )

    Array(hash[:findings]).each do |finding|
      run.cdef_coverage_results.create!(
        service_key: finding[:service],
        verdict: finding[:verdict],
        resource_count: finding[:resource_count].to_i,
        resource_types: Array(finding[:resource_types]),
        inferred: !!finding[:inferred],
        cdef_documents: Array(finding[:cdef_documents])
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
