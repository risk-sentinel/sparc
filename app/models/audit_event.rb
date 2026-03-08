# frozen_string_literal: true

# Records authentication and authorization events for compliance auditing.
# Every login, logout, password change, and role change is logged here.
#
# SPARC should practice what it preaches — if we mandate audit trails
# in the documents we manage, we should have one ourselves.
class AuditEvent < ApplicationRecord
  belongs_to :user, optional: true # nullable for failed logins

  validates :action, presence: true

  ACTIONS = %w[
    login_success
    login_failure
    logout
    password_change
    role_grant
    role_revoke
    user_suspended
    user_reactivated
    admin_bootstrap
  ].freeze

  validates :action, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :logins, -> { where(action: %w[login_success login_failure]) }

  # Convenience factory for logging events throughout the app.
  #
  #   AuditEvent.log(user: current_user, action: "login_success",
  #                  provider: "local", ip_address: request.remote_ip)
  def self.log(user: nil, action:, provider: nil, ip_address: nil, user_agent: nil, metadata: {})
    create!(
      user: user,
      action: action,
      provider: provider,
      ip_address: ip_address,
      user_agent: user_agent,
      metadata: metadata
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[AuditEvent] Failed to log #{action}: #{e.message}")
  end
end
