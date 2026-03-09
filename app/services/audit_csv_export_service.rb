# frozen_string_literal: true

require "csv"

# Exports audit events to CSV for compliance reporting.
#
# Usage:
#   csv = AuditCsvExportService.new(AuditEvent.recent.limit(1000)).export
#
class AuditCsvExportService
  HEADERS = %w[
    timestamp
    user_email
    action
    category
    subject_type
    subject_id
    ip_address
    user_agent
    metadata
  ].freeze

  def initialize(scope)
    @scope = scope
  end

  def export
    CSV.generate do |csv|
      csv << HEADERS
      @scope.includes(:user).find_each do |event|
        csv << [
          event.created_at.iso8601,
          event.user&.email || "(system)",
          event.action,
          event.category,
          event.subject_type,
          event.subject_id,
          event.ip_address,
          event.user_agent,
          event.metadata.to_json
        ]
      end
    end
  end
end
