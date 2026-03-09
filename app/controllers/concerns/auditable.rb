# frozen_string_literal: true

# Provides a DRY audit logging helper for controllers. Automatically captures
# the current user, IP address, and user agent from the request context.
#
# Usage:
#   audit_log("ssp_document_created", subject: @ssp_document,
#             metadata: { name: @ssp_document.name })
#
module Auditable
  extend ActiveSupport::Concern

  private

  def audit_log(action, subject: nil, metadata: {})
    AuditEvent.log(
      user: current_user,
      action: action,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      subject: subject,
      metadata: metadata
    )
  end
end
