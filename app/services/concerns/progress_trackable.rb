# frozen_string_literal: true

# Shared progress-tracking logic for parser services.
#
# Reports processing stages to the document's `metadata_extra` JSONB column
# using `update_columns` (bypasses callbacks for speed — this is a heartbeat,
# not a domain update).
#
# Uses the `processing_*` namespace in metadata_extra to avoid collision with
# the CCI Refresh feature, which uses the `refresh_*` namespace.
#
# Usage in a parser service:
#   include ProgressTrackable
#
#   def parse
#     update_processing_stage!(:reading_file, "Opening spreadsheet...")
#     # ... parse logic ...
#     update_processing_progress!("Parsed 5000 of 50000 rows...")
#     # ... more parsing ...
#     update_processing_stage!(:creating_records, "Creating 500 controls...")
#     # ... batch insert ...
#   end
#
module ProgressTrackable
  extend ActiveSupport::Concern

  PROCESSING_STAGES = {
    reading_file:     "Reading file...",
    validating:       "Validating structure...",
    parsing:          "Parsing records...",
    creating_records: "Creating database records...",
    finalizing:       "Finalizing import..."
  }.freeze

  private

  # Set the current processing stage with an optional custom message.
  #
  # @param stage [Symbol] One of PROCESSING_STAGES keys (or any descriptive symbol)
  # @param custom_message [String, nil] Override the default stage message
  def update_processing_stage!(stage, custom_message = nil)
    return unless @document.respond_to?(:metadata_extra)

    message = custom_message || PROCESSING_STAGES[stage] || stage.to_s.humanize
    meta = (@document.metadata_extra || {}).merge(
      "processing_stage"      => stage.to_s,
      "processing_message"    => message,
      "processing_updated_at" => Time.current.iso8601
    )
    @document.update_columns(metadata_extra: meta)
    Rails.logger.info("[ProgressTrackable] #{@document.class.name}##{@document.id} stage: #{stage} — #{message}")
  end

  # Update only the progress message (for row-count heartbeats without changing stage).
  #
  # @param message [String] The progress message to display
  def update_processing_progress!(message)
    return unless @document.respond_to?(:metadata_extra)

    meta = (@document.metadata_extra || {}).merge(
      "processing_message"    => message,
      "processing_updated_at" => Time.current.iso8601
    )
    @document.update_columns(metadata_extra: meta)
  end
end
