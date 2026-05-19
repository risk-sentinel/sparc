# frozen_string_literal: true

# Background job for refreshing a Converter's entries from an external source.
# Dispatches to the appropriate refresh service by converter_type:
#
#   cci_to_nist               -> CciRefreshService             (DISA XML)
#   aws_config_to_nist        -> AwsConfigRefreshService       (mitre/heimdall2 TS)
#   aws_security_hub_to_nist  -> AwsSecurityHubRefreshService  (AWS docs scrape)
#
# Lifecycle: pending -> processing -> complete / failed
# Progress stages are tracked in converter.metadata_extra["refresh_stage"]
# so the UI can show live updates via auto-refresh.
class ConverterRefreshJob < ApplicationJob
  queue_as :default

  SERVICE_BY_TYPE = {
    "cci_to_nist"              => "CciRefreshService",
    "aws_config_to_nist"       => "AwsConfigRefreshService",
    "aws_security_hub_to_nist" => "AwsSecurityHubRefreshService"
  }.freeze

  def perform(converter_id)
    converter = Converter.find(converter_id)
    converter.update!(status: "processing", error_message: nil)

    service_name = SERVICE_BY_TYPE[converter.converter_type]
    unless service_name
      raise "No refresh service registered for converter_type=#{converter.converter_type}"
    end

    service_class = service_name.constantize
    stats = service_class.call(converter)

    Rails.logger.info(
      "[ConverterRefreshJob] Successfully refreshed converter #{converter_id} " \
      "(#{converter.converter_type}): #{stats.inspect}"
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
