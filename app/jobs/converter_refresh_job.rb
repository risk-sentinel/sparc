# frozen_string_literal: true

# Background job for refreshing a Converter's entries from an external source.
# Currently supports CCI → NIST refresh from DISA's official CCI XML.
#
# Lifecycle: pending → processing → complete / failed
# Progress stages are tracked in converter.metadata_extra["refresh_stage"]
# so the UI can show live updates via auto-refresh.
#
class ConverterRefreshJob < ApplicationJob
  queue_as :default

  def perform(converter_id)
    converter = Converter.find(converter_id)
    converter.update!(status: "processing", error_message: nil)

    stats = CciRefreshService.call(converter)

    Rails.logger.info(
      "[ConverterRefreshJob] Successfully refreshed converter #{converter_id}: " \
      "#{stats[:total]} CCIs, #{stats[:entries]} total entries"
    )
  rescue StandardError => e
    if converter
      converter.update_columns(
        status: "failed",
        error_message: e.message,
        metadata_extra: (converter.metadata_extra || {}).merge(
          "refresh_stage" => "failed",
          "refresh_message" => e.message,
          "refresh_failed_at" => Time.current.iso8601
        )
      )
    end
    Rails.logger.error("[ConverterRefreshJob] Failed for converter #{converter_id}: #{e.message}")
  end
end
