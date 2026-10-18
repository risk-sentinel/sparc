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

  # What a release before #1223 wrote when it could not load a class: the bare
  # form, nothing after it. A rolling deploy produced it on rows the NEW release
  # can run perfectly well. Current releases always say why after a colon.
  LEGACY_NOT_LOADABLE = /\AClass \S+ not loadable\z/

  # #1223 — rows a runner on THIS release should take up between boots:
  # pending, or failed by an older release's worker during a rolling deploy.
  # Not a genuine failure (those retry once per boot, as before), and not a row
  # a newer release registered.
  def self.awaiting_this_release
    where(status: %w[pending failed]).select do |run|
      (run.pending? || run.error_message.to_s.match?(LEGACY_NOT_LOADABLE)) && !run.registered_by_newer_release?
    end
  end

  def pending?   = status == "pending"
  def running?   = status == "running"
  def completed? = status == "completed"
  def failed?    = status == "failed"

  # #1223 — registered by a release NEWER than this one. The class a container
  # cannot load is then not a fault in the migration, only a sign the container
  # is older than the row. Unknown (nil: registered before the column existed,
  # or a database an older release migrated) is not newer.
  def registered_by_newer_release?
    return false unless has_attribute?(:registered_release) && registered_release.present?

    Gem::Version.new(registered_release) > Gem::Version.new(SparcConfig::VERSION)
  rescue ArgumentError
    false
  end

  # Total wall-clock time the runner spent on this migration,
  # if it has completed (or failed). Nil while pending / running.
  def duration_seconds
    return nil unless started_at && completed_at

    (completed_at - started_at).to_i
  end
end
