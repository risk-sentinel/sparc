# frozen_string_literal: true

# Records authentication, authorization, and resource events for compliance auditing.
# Every login, logout, password change, role change, and resource CRUD is logged here.
#
# SPARC should practice what it preaches — if we mandate audit trails
# in the documents we manage, we should have one ourselves.
#
# Immutable by design: no updated_at column, no update methods.
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
    admin_bootstrap
    ssp_document_created
    ssp_document_updated
    ssp_document_deleted
    ssp_document_exported
    ssp_document_imported
    sar_document_created
    sar_document_updated
    sar_document_deleted
    sar_document_exported
    sar_document_imported
    cdef_document_created
    cdef_document_updated
    cdef_document_deleted
    cdef_document_exported
    cdef_document_copied
    sap_document_created
    sap_document_updated
    sap_document_deleted
    sap_document_exported
    sap_document_imported
    poam_document_created
    poam_document_updated
    poam_document_deleted
    poam_document_exported
    profile_document_created
    profile_document_updated
    profile_document_deleted
    profile_document_exported
    profile_document_copied
    control_catalog_created
    control_catalog_updated
    control_catalog_deleted
    control_catalog_exported
    control_catalog_imported
    control_family_created
    control_family_updated
    control_family_deleted
    catalog_control_created
    catalog_control_updated
    catalog_control_deleted
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
    profile_control_created
    profile_control_updated
    profile_control_deleted
  ].freeze

  validates :action, inclusion: { in: ACTIONS }

  # ── Categories (for admin UI grouping) ─────────────────────────────────
  ACTION_CATEGORIES = {
    "Authentication" => %w[login_success login_failure logout password_change],
    "Authorization" => %w[authorization_failure],
    "User Management" => %w[user_suspended user_reactivated admin_bootstrap],
    "Role Management" => %w[role_grant role_revoke role_created role_updated role_deleted],
    "Auth Boundary Members" => %w[authorization_boundary_member_added authorization_boundary_member_removed
                                  authorization_boundary_membership_created authorization_boundary_membership_updated
                                  authorization_boundary_membership_deleted
                                  project_member_added project_member_removed
                                  project_membership_created project_membership_updated
                                  project_membership_deleted],
    "SSP Documents" => %w[ssp_document_created ssp_document_updated ssp_document_deleted
                          ssp_document_exported ssp_document_imported],
    "SAR Documents" => %w[sar_document_created sar_document_updated sar_document_deleted
                          sar_document_exported sar_document_imported],
    "CDEF Documents" => %w[cdef_document_created cdef_document_updated cdef_document_deleted
                           cdef_document_exported cdef_document_copied],
    "SAP Documents" => %w[sap_document_created sap_document_updated sap_document_deleted
                          sap_document_exported sap_document_imported],
    "POAM Documents" => %w[poam_document_created poam_document_updated poam_document_deleted
                           poam_document_exported poam_item_created poam_item_updated
                           poam_item_deleted],
    "Profiles" => %w[profile_document_created profile_document_updated profile_document_deleted
                     profile_document_exported profile_document_copied
                     profile_control_created profile_control_updated profile_control_deleted],
    "Control Catalogs" => %w[control_catalog_created control_catalog_updated control_catalog_deleted
                             control_catalog_exported control_catalog_imported
                             control_family_created control_family_updated control_family_deleted
                             catalog_control_created catalog_control_updated catalog_control_deleted],
    "Control Mappings" => %w[control_mapping_created control_mapping_updated control_mapping_deleted
                             control_mapping_exported control_mapping_published
                             control_mapping_deprecated mapping_entry_created mapping_entry_deleted],
    "Evidence" => %w[evidence_created evidence_updated evidence_deleted
                     attestation_created attestation_deleted],
    "Authorization Boundaries" => %w[authorization_boundary_created authorization_boundary_updated
                                     authorization_boundary_deleted project_created project_updated
                                     project_deleted boundary_created boundary_updated boundary_deleted]
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
