# frozen_string_literal: true

# #1268 — what the last AWS Labs CDEF refresh did, read from the audit events
# the refresh writes (CdefDocumentsController#refresh_aws_labs,
# AwsLabsCdefRefreshJob). Shown to whoever may press Refresh Now, beside the
# button, so "queued" is never the last word on a refresh that never started,
# kept nothing, or failed.
class AwsLabsRefreshStatus
  ACTIONS = %w[
    aws_labs_cdef_refresh_requested
    aws_labs_cdef_refresh_enqueue_failed
    aws_labs_cdef_refresh_started
    aws_labs_cdef_refresh_completed
    aws_labs_cdef_refresh_kept_nothing
    aws_labs_cdef_refresh_failed
  ].freeze

  # A full refresh takes 85–100 seconds; well past that, a queued or running
  # refresh is reported as stuck rather than in progress.
  STALE_AFTER = 15.minutes

  attr_reader :event

  def self.current
    new(AuditEvent.where(action: ACTIONS).order(created_at: :desc, id: :desc).first)
  end

  def initialize(event)
    @event = event
  end

  # :ok, :info or :warning — how the screen shows it.
  def tone
    case state
    when :completed, :unchanged then :ok
    when :queued, :running, :never then :info
    else :warning
    end
  end

  def state
    return :never unless event

    case event.action
    when "aws_labs_cdef_refresh_requested" then stale? ? :never_started : :queued
    when "aws_labs_cdef_refresh_enqueue_failed" then :enqueue_failed
    when "aws_labs_cdef_refresh_started" then stale? ? :stuck : :running
    when "aws_labs_cdef_refresh_kept_nothing" then :kept_nothing
    when "aws_labs_cdef_refresh_failed" then :failed
    else meta["discovered"].to_i.zero? ? :unchanged : :completed
    end
  end

  def message
    at = event&.created_at&.utc&.strftime("%Y-%m-%d %H:%M UTC")
    case state
    when :never then "No AWS Labs refresh has been recorded yet."
    when :queued then "Refresh queued at #{at}; waiting for the job worker to start it."
    when :never_started then "Refresh queued at #{at} and never started. Check that the job worker is running."
    when :enqueue_failed then "Refresh at #{at} could not be queued: #{meta['error_message'] || 'the job queue refused it'}."
    when :running then "Refresh running since #{at}. A full refresh takes one to two minutes."
    when :stuck then "Refresh started at #{at} and has not finished. Check the job worker's log."
    when :unchanged then "Last refresh #{at}: upstream unchanged since the previous refresh."
    when :completed then "Last refresh #{at}: #{meta['imported'].to_i} imported, #{meta['skipped_unchanged'].to_i} unchanged, " \
                         "#{meta['errors'].to_i} failed, of #{meta['discovered'].to_i} upstream files.#{version_note}"
    when :kept_nothing then "Last refresh #{at} imported nothing: the version filter kept none of the " \
                            "#{meta['discovered'].to_i} upstream files.#{version_note}"
    when :failed then "Last refresh #{at} failed: #{meta['error_class']}: #{meta['error_message']}"
    end
  end

  private

  def meta = event&.metadata || {}

  def stale? = event.created_at < STALE_AFTER.ago

  def version_note
    skipped = meta["skipped_by_version"].presence
    return "" unless skipped

    found = skipped.map { |v, n| "#{v} (#{n})" }.join(", ")
    allowed = Array(meta["allowed_versions"]).presence&.join(", ") || "any"
    " Skipped by OSCAL version: #{found}; SPARC_AWS_LABS_OSCAL_VERSIONS allows #{allowed}."
  end
end
