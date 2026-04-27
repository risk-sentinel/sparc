# frozen_string_literal: true

# Records authentication, authorization, and resource events for compliance auditing.
# Every login, logout, password change, role change, and resource CRUD is logged here.
#
# SPARC should practice what it preaches — if we mandate audit trails
# in the documents we manage, we should have one ourselves.
#
# Immutable by design: no updated_at column, no update methods.
#
# NIST 800-53 Controls:
#   AU-2 Event Logging (139 auditable event types)
#   AU-3 Content of Audit Records (user, action, IP, timestamp, metadata)
#   AU-9 Protection of Audit Information (append-only, immutable records)
#   AU-12 Audit Record Generation (AuditEvent.log factory)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class AuditEvent < ApplicationRecord
  belongs_to :user, optional: true # nullable for failed logins

  validates :action, presence: true

  # ── Actions ────────────────────────────────────────────────────────────
  # New actions use "authorization_boundary_*" naming; old "project_*" actions
  # are kept for backward compatibility with historical audit records.
  ACTIONS = %w[
    login_success
    login_failure
    logout
    password_change
    authorization_failure
    role_grant
    role_revoke
    role_created
    role_updated
    role_deleted
    authorization_boundary_member_added
    authorization_boundary_member_removed
    project_member_added
    project_member_removed
    user_suspended
    user_reactivated
    user_deactivated
    user_auto_deactivated
    user_password_expired
    admin_bootstrap
    admin_password_reset
    admin_credential_synced_from_env
    admin_credential_rotated
    ssp_document_created
    ssp_document_updated
    ssp_document_deleted
    ssp_document_delete_blocked
    ssp_document_exported
    ssp_document_imported
    sar_document_created
    sar_document_updated
    sar_document_deleted
    sar_document_delete_blocked
    sar_document_exported
    sar_document_imported
    cdef_document_created
    cdef_document_updated
    cdef_document_deleted
    cdef_document_delete_blocked
    cdef_document_exported
    cdef_document_imported
    cdef_document_copied
    sap_document_created
    sap_document_updated
    sap_document_deleted
    sap_document_delete_blocked
    sap_document_exported
    sap_document_imported
    poam_document_created
    poam_document_updated
    poam_document_deleted
    poam_document_delete_blocked
    poam_document_exported
    poam_document_imported
    profile_document_created
    profile_document_updated
    profile_document_deleted
    profile_document_delete_blocked
    profile_document_exported
    profile_document_imported
    profile_document_copied
    profile_controls_bulk_updated
    control_catalog_created
    control_catalog_updated
    control_catalog_deleted
    control_catalog_delete_blocked
    control_catalog_exported
    control_catalog_imported
    control_family_created
    control_family_updated
    control_family_deleted
    catalog_control_created
    catalog_control_updated
    catalog_control_deleted
    catalog_control_baseline_updated
    catalog_control_baselines_bulk_updated
    control_mapping_created
    control_mapping_updated
    control_mapping_deleted
    control_mapping_exported
    control_mapping_published
    control_mapping_deprecated
    mapping_entry_created
    mapping_entry_deleted
    evidence_created
    evidence_updated
    evidence_deleted
    attestation_created
    attestation_deleted
    authorization_boundary_created
    authorization_boundary_updated
    authorization_boundary_deleted
    project_created
    project_updated
    project_deleted
    boundary_created
    boundary_updated
    boundary_deleted
    authorization_boundary_membership_created
    authorization_boundary_membership_updated
    authorization_boundary_membership_deleted
    project_membership_created
    project_membership_updated
    project_membership_deleted
    poam_item_created
    poam_item_updated
    poam_item_deleted
    poam_risk_created
    poam_risk_updated
    poam_risk_deleted
    poam_remediation_created
    poam_remediation_updated
    poam_remediation_deleted
    poam_milestone_created
    poam_milestone_updated
    poam_milestone_deleted
    poam_observation_created
    poam_observation_updated
    poam_observation_deleted
    profile_control_created
    profile_control_updated
    profile_control_deleted
    organization_created
    organization_updated
    organization_deactivated
    organization_reactivated
    organization_member_added
    organization_member_removed
    ssp_document_published
    sar_document_published
    cdef_document_published
    sap_document_published
    poam_document_published
    profile_document_published
    control_catalog_published
    service_account_created
    service_account_updated
    service_account_disabled
    service_account_enabled
    service_account_deleted
    service_account_token_regenerated
    service_account_auto_disabled
  ].freeze

  validates :action, inclusion: { in: ACTIONS }

  # ── Categories (for admin UI grouping) ─────────────────────────────────
  ACTION_CATEGORIES = {
    "Authentication" => %w[login_success login_failure logout password_change],
    "Authorization" => %w[authorization_failure],
    "User Management" => %w[user_suspended user_reactivated user_deactivated
                            user_auto_deactivated user_password_expired admin_bootstrap
                            admin_password_reset admin_credential_synced_from_env
                            admin_credential_rotated],
    "Role Management" => %w[role_grant role_revoke role_created role_updated role_deleted],
    "Auth Boundary Members" => %w[authorization_boundary_member_added authorization_boundary_member_removed
                                  authorization_boundary_membership_created authorization_boundary_membership_updated
                                  authorization_boundary_membership_deleted
                                  project_member_added project_member_removed
                                  project_membership_created project_membership_updated
                                  project_membership_deleted],
    "SSP Documents" => %w[ssp_document_created ssp_document_updated ssp_document_deleted
                          ssp_document_delete_blocked ssp_document_exported ssp_document_imported
                          ssp_document_published],
    "SAR Documents" => %w[sar_document_created sar_document_updated sar_document_deleted
                          sar_document_delete_blocked sar_document_exported sar_document_imported
                          sar_document_published],
    "CDEF Documents" => %w[cdef_document_created cdef_document_updated cdef_document_deleted
                           cdef_document_delete_blocked
                           cdef_document_exported cdef_document_imported cdef_document_copied
                           cdef_document_published],
    "SAP Documents" => %w[sap_document_created sap_document_updated sap_document_deleted
                          sap_document_delete_blocked sap_document_exported sap_document_imported
                          sap_document_published],
    "POAM Documents" => %w[poam_document_created poam_document_updated poam_document_deleted
                           poam_document_delete_blocked
                           poam_document_exported poam_document_imported poam_item_created
                           poam_item_updated poam_item_deleted
                           poam_risk_created poam_risk_updated poam_risk_deleted
                           poam_remediation_created poam_remediation_updated poam_remediation_deleted
                           poam_milestone_created poam_milestone_updated poam_milestone_deleted
                           poam_observation_created poam_observation_updated poam_observation_deleted
                           poam_document_published],
    "Profiles" => %w[profile_document_created profile_document_updated profile_document_deleted
                     profile_document_delete_blocked
                     profile_document_exported profile_document_imported profile_document_copied
                     profile_controls_bulk_updated
                     profile_control_created profile_control_updated profile_control_deleted
                     profile_document_published],
    "Control Catalogs" => %w[control_catalog_created control_catalog_updated control_catalog_deleted
                             control_catalog_delete_blocked
                             control_catalog_exported control_catalog_imported
                             control_family_created control_family_updated control_family_deleted
                             catalog_control_created catalog_control_updated catalog_control_deleted
                             catalog_control_baseline_updated catalog_control_baselines_bulk_updated
                             control_catalog_published],
    "Control Mappings" => %w[control_mapping_created control_mapping_updated control_mapping_deleted
                             control_mapping_exported control_mapping_published
                             control_mapping_deprecated mapping_entry_created mapping_entry_deleted],
    "Evidence" => %w[evidence_created evidence_updated evidence_deleted
                     attestation_created attestation_deleted],
    "Authorization Boundaries" => %w[authorization_boundary_created authorization_boundary_updated
                                     authorization_boundary_deleted project_created project_updated
                                     project_deleted boundary_created boundary_updated boundary_deleted],
    "Organizations" => %w[organization_created organization_updated organization_deactivated
                          organization_reactivated organization_member_added organization_member_removed],
    "Service Accounts" => %w[service_account_created service_account_updated service_account_disabled
                             service_account_enabled service_account_deleted
                             service_account_token_regenerated service_account_auto_disabled]
  }.freeze

  # ── Scopes ─────────────────────────────────────────────────────────────
  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :logins, -> { where(action: %w[login_success login_failure]) }

  scope :for_subject, ->(subject) {
    where(subject_type: subject.class.name, subject_id: subject.id)
  }

  scope :by_subject_type, ->(type) { where(subject_type: type) }

  scope :by_category, ->(category) {
    actions = ACTION_CATEGORIES[category]
    actions ? where(action: actions) : none
  }

  scope :in_date_range, ->(start_date, end_date) {
    scope = all
    scope = scope.where("created_at >= ?", start_date.to_date.beginning_of_day) if start_date.present?
    scope = scope.where("created_at <= ?", end_date.to_date.end_of_day) if end_date.present?
    scope
  }

  scope :search, ->(query) {
    return all if query.blank?
    where("action ILIKE :q OR metadata::text ILIKE :q", q: "%#{query}%")
  }

  # ── Instance Methods ───────────────────────────────────────────────────

  # Returns the human-readable category for this event's action.
  def category
    ACTION_CATEGORIES.each do |cat, actions|
      return cat if actions.include?(action)
    end
    "Other"
  end

  # ── Factory ────────────────────────────────────────────────────────────

  # Convenience factory for logging events throughout the app.
  #
  #   AuditEvent.log(user: current_user, action: "login_success",
  #                  provider: "local", ip_address: request.remote_ip,
  #                  subject: @ssp_document)
  def self.log(user: nil, action:, provider: nil, ip_address: nil,
               user_agent: nil, metadata: {}, subject: nil)
    event = create!(
      user: user,
      action: action,
      provider: provider,
      ip_address: ip_address,
      user_agent: user_agent,
      metadata: metadata,
      subject_type: subject&.class&.name,
      subject_id: subject&.id
    )

    # Emit structured JSON to Rails log so audit events flow through
    # container logs → CloudWatch / Datadog / any log aggregator.
    Rails.logger.info(
      {
        audit_event: {
          id: event.id,
          action: event.action,
          category: event.category,
          user_id: event.user_id,
          user_email: event.user&.email,
          subject_type: event.subject_type,
          subject_id: event.subject_id,
          ip_address: event.ip_address,
          metadata: event.metadata,
          timestamp: event.created_at.iso8601
        }
      }.to_json
    )

    event
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[AuditEvent] Failed to log #{action}: #{e.message}")
  end
end
