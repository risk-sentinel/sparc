# frozen_string_literal: true

# Tracking record for a deferred data migration (v1.8.3).
#
# One row per migration class that `include DeferredDataMigration`.
# Lifecycle: pending → running → completed (or → failed).
#
# Reflects the SeedSection pattern intentionally — same shape,
# same operator UX — but scoped to ActiveRecord::Migration
# subclasses that opt into deferred execution rather than the
# seed-runner sections.
#
# NIST 800-53 AU-2: data-migration lifecycle is observable from
#                   the admin UI + structured JSON logs emitted by
#                   the runner.
class DataMigrationRun < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  validates :name, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :records_processed, numericality: { greater_than_or_equal_to: 0 }

  scope :pending,   -> { where(status: "pending") }
  scope :running,   -> { where(status: "running") }
  scope :completed, -> { where(status: "completed") }
  scope :failed,    -> { where(status: "failed") }

  scope :recent, -> { order(created_at: :desc) }

  def pending?   = status == "pending"
  def running?   = status == "running"
  def completed? = status == "completed"
  def failed?    = status == "failed"

  # Total wall-clock time the runner spent on this migration,
  # if it has completed (or failed). Nil while pending / running.
  def duration_seconds
    return nil unless started_at && completed_at

    (completed_at - started_at).to_i
  end
end
