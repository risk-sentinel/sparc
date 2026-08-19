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
#   AU-2 Event Logging (286 auditable event types across 28 categories)
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
  # `action` is validated against this list (see the inclusion validation
  # below), so an action missing from it fails validation and the whole write
  # fails — not just the audit. A new audited action MUST be added here AND to
  # ACTION_CATEGORIES, which a spec enforces.
  #
  # #982 — that pairing spec was not enough, and 69 emitted actions proved it.
  # Comparing ACTIONS to ACTION_CATEGORIES cannot see an action missing from
  # BOTH: the two constants agreed with each other while the code emitted names
  # neither had heard of. `.log` rescues the resulting RecordInvalid internally,
  # so those writes were dropped in every environment with nothing raised — API
  # token create/revoke, every finding disposition, every federation peer
  # change, and the whole back-matter promotion workflow recorded nothing.
  # `spec/models/audit_event_spec.rb` now scans the SOURCE for emitted actions,
  # because only the source knows what is really emitted.
  #
  # NOTE: this is a `%w[]` literal — it has no comment syntax. A `#` inside it
  # becomes an array element, not a comment.
  ACTIONS = %w[
    login_success
    login_failure
    logout
    password_change
    webauthn_key_registered
    webauthn_key_revoked
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
    user_created
    user_suspended
    user_reactivated
    user_deactivated
    user_auto_deactivated
    user_deactivate_refused
    user_suspend_refused
    user_password_expired
    admin_bootstrap
    admin_password_reset
    admin_webauthn_reset
    admin_credential_synced_from_env
    admin_temporary_password_issued
    admin_password_reset_emailed
    password_reset_redeemed
    admin_credential_rotated
    sparc_hash_rotated
    ssp_document_baseline_declared
    sar_document_baseline_declared
    sap_document_baseline_declared
    poam_document_baseline_declared
    cdef_document_baseline_declared
    profile_document_baseline_declared

    ssp_document_created
    ssp_document_updated
    ssp_document_deleted
    ssp_document_delete_blocked
    ssp_document_exported
    ssp_document_imported
    ssp_document_boundary_attached
    boundary_less_documents_reported
    unscoped_authoritative_back_matter_reported
    sar_document_boundary_attached
    sar_document_created
    sar_document_updated
    sar_document_deleted
    sar_document_delete_blocked
    sar_document_exported
    sar_document_imported
    cdef_document_scope_updated
    cdef_document_created
    cdef_document_updated
    cdef_document_deleted
    cdef_coverage_analyzed
    cdef_coverage_run_saved
    cdef_coverage_run_deleted
    cdef_document_delete_blocked
    cdef_document_exported
    cdef_document_imported
    cdef_document_copied
    cdef_back_matter_promoted
    cdef_bulk_apply_converter_previewed
    cdef_bulk_apply_converter_applied
    aws_labs_cdef_refresh_requested
    aws_labs_cdef_refresh_degraded
    control_resource_created
    control_resource_linked
    control_resource_unlinked
    authoritative_source_created
    data_migration_completed
    sap_document_boundary_attached
    sap_document_created
    sap_document_generated
    sap_document_updated
    sap_document_deleted
    sap_document_delete_blocked
    sap_document_exported
    sap_document_imported
    poam_document_boundary_attached
    poam_document_created
    poam_document_generated
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
    evidence_upload_rejected
    incomplete_evidence_reported
    attestation_created
    attestation_deleted
    authorization_boundary_created
    authorization_boundary_updated
    authorization_boundary_deleted
    authorization_boundary_delete_blocked
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
    poam_finding_created
    poam_finding_updated
    poam_finding_deleted
    poam_local_component_created
    poam_local_component_updated
    poam_local_component_deleted
    poam_document_viewed_by_leveraging_user
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
    control_catalog_submitted_for_review
    control_catalog_approved
    control_catalog_rejected
    profile_document_submitted_for_review
    profile_document_approved
    profile_document_rejected
    cdef_document_submitted_for_review
    cdef_document_approved
    cdef_document_rejected
    service_account_created
    service_account_updated
    service_account_disabled
    service_account_enabled
    service_account_deleted
    service_account_token_regenerated
    service_account_auto_disabled
    translation_hdf_to_oscal_sar
    translation_hdf_to_oscal_poam
    translation_hdf_amendments_to_oscal_poam
    translation_oscal_poam_to_hdf_amendments
    converter_refresh_started
    api_user_created
    api_user_updated
    api_user_deactivated
    api_session_bridged
    api_session_bridge_failed
    api_authorization_boundary_created
    api_authorization_boundary_updated
    api_authorization_boundary_deleted
    api_authorization_boundary_membership_created
    api_authorization_boundary_membership_updated
    api_authorization_boundary_membership_deleted
    api_control_family_created
    api_control_family_updated
    api_control_family_deleted
    api_catalog_control_created
    api_catalog_control_updated
    api_catalog_control_deleted

    api_authorization_boundary_org_assigned
    organization_boundary_assigned
    api_token_created
    api_token_revoked
    ato_package_created
    ato_package_exported

    authoritative_sources_export
    authoritative_sources_import

    back_matter_resource_created
    back_matter_resource_updated
    back_matter_resource_deleted
    back_matter_resource_linked
    back_matter_resource_unlinked
    back_matter_resource_archived
    back_matter_resource_restored
    back_matter_resource_promotion_requested
    back_matter_resource_promotion_approved
    back_matter_resource_promotion_rejected
    back_matter_resources_bulk_imported

    cdef_control_updated
    cdef_statement_updated
    cdef_document_authored
    cdef_document_copy_failed
    cdef_document_created_from_profile
    cdef_control_implementation_sourced_from_profile

    converter_created
    converter_updated
    converter_deleted
    converter_imported
    converter_exported
    converter_entry_created
    converter_entry_deleted
    stig_imported

    evidence_control_link_created
    evidence_control_link_deleted

    federation_peer_created
    federation_peer_updated
    federation_peer_deleted
    federation_peer_synced

    finding_disposition_set
    finding_disposition_cleared
    finding_disposition_approved
    finding_disposition_rejected
    scan_run_ingested
    hdf_aggregation_enqueued
    hdf_aggregation_run
    hdf_amendments_exported
    hdf_package_exported

    ksi_validation_created
    ksi_validation_updated
    ksi_validation_deleted

    mapping_entry_updated
    api_mapping_entry_created
    api_mapping_entry_updated
    api_mapping_entry_deleted

    remediation_timeline_updated

    sap_document_reprocessed
    sap_objective_updated
    sar_document_reprocessed
    sar_objective_updated

    ssp_document_created_from_profile
    ssp_document_populated_from_profile
    ssp_statement_updated
    ssp_statement_reset_to_source
    ssp_inherited_refreshed

    ssp_document_fields_imported
    sar_document_fields_imported
    sap_document_fields_imported
    cdef_document_fields_imported
  ].freeze

  validates :action, inclusion: { in: ACTIONS }

  # ── Categories (for admin UI grouping) ─────────────────────────────────
  ACTION_CATEGORIES = {
    "Authentication" => %w[login_success login_failure logout password_change
                           admin_temporary_password_issued admin_password_reset_emailed
                           password_reset_redeemed
                            webauthn_key_registered webauthn_key_revoked
                            api_session_bridged api_session_bridge_failed],
    "Authorization" => %w[authorization_failure],
    "User Management" => %w[user_created user_suspended user_reactivated user_deactivated
                            user_auto_deactivated user_deactivate_refused user_suspend_refused
                            user_password_expired admin_bootstrap
                            admin_password_reset admin_webauthn_reset admin_credential_synced_from_env
                            admin_credential_rotated sparc_hash_rotated
                            api_user_created api_user_updated api_user_deactivated],
    "Auth Boundary Admin" => %w[api_authorization_boundary_created
                                api_authorization_boundary_updated
                                api_authorization_boundary_deleted
                                api_authorization_boundary_org_assigned],
    "Catalog Management" => %w[api_control_family_created api_control_family_updated
                              api_control_family_deleted
                              api_catalog_control_created api_catalog_control_updated
                              api_catalog_control_deleted],
    "Role Management" => %w[role_grant role_revoke role_created role_updated role_deleted],
    "Auth Boundary Members" => %w[authorization_boundary_member_added authorization_boundary_member_removed
                                  authorization_boundary_membership_created authorization_boundary_membership_updated
                                  authorization_boundary_membership_deleted
                                  api_authorization_boundary_membership_created
                                  api_authorization_boundary_membership_updated
                                  api_authorization_boundary_membership_deleted
                                  project_member_added project_member_removed
                                  project_membership_created project_membership_updated
                                  project_membership_deleted],
    "SSP Documents" => %w[ssp_document_created ssp_document_updated ssp_document_deleted
                          ssp_document_delete_blocked ssp_document_exported ssp_document_imported
                          ssp_document_published ssp_document_baseline_declared
                          ssp_document_boundary_attached
                          boundary_less_documents_reported
                          unscoped_authoritative_back_matter_reported
                          ssp_document_created_from_profile ssp_document_populated_from_profile
                          ssp_statement_updated ssp_statement_reset_to_source
                          ssp_inherited_refreshed ssp_document_fields_imported],
    "SAR Documents" => %w[sar_document_created sar_document_updated sar_document_deleted
                          sar_document_delete_blocked sar_document_exported sar_document_imported
                          sar_document_published sar_document_baseline_declared
                          sar_document_boundary_attached
                          sar_document_reprocessed sar_objective_updated
                          sar_document_fields_imported],
    "CDEF Documents" => %w[cdef_document_created cdef_document_updated cdef_document_deleted
                           cdef_coverage_analyzed cdef_coverage_run_saved cdef_coverage_run_deleted
                           cdef_document_delete_blocked
                           cdef_document_exported cdef_document_imported cdef_document_copied
                           cdef_document_published cdef_back_matter_promoted
                           cdef_document_submitted_for_review cdef_document_approved cdef_document_rejected
                           cdef_bulk_apply_converter_previewed
                           cdef_bulk_apply_converter_applied
                           aws_labs_cdef_refresh_requested
                           aws_labs_cdef_refresh_degraded
                           control_resource_created control_resource_linked
                           control_resource_unlinked cdef_document_baseline_declared
                           cdef_document_scope_updated
                           cdef_control_updated cdef_statement_updated
                           cdef_document_authored cdef_document_copy_failed
                           cdef_document_created_from_profile
                           cdef_control_implementation_sourced_from_profile
                           cdef_document_fields_imported],
    "SAP Documents" => %w[sap_document_created sap_document_generated sap_document_updated
                          sap_document_deleted sap_document_delete_blocked sap_document_exported
                          sap_document_imported sap_document_published
                          sap_document_baseline_declared sap_document_boundary_attached
                          sap_document_reprocessed sap_objective_updated
                          sap_document_fields_imported],
    "POAM Documents" => %w[poam_document_created poam_document_generated poam_document_updated
                           poam_document_deleted poam_document_delete_blocked
                           poam_document_exported poam_document_imported poam_item_created
                           poam_item_updated poam_item_deleted
                           poam_risk_created poam_risk_updated poam_risk_deleted
                           poam_remediation_created poam_remediation_updated poam_remediation_deleted
                           poam_milestone_created poam_milestone_updated poam_milestone_deleted
                           poam_observation_created poam_observation_updated poam_observation_deleted
                           poam_finding_created poam_finding_updated poam_finding_deleted
                           poam_local_component_created poam_local_component_updated poam_local_component_deleted
                           poam_document_viewed_by_leveraging_user
                           poam_document_published poam_document_baseline_declared
                           poam_document_boundary_attached
                           remediation_timeline_updated],
    "Profiles" => %w[profile_document_created profile_document_updated profile_document_deleted
                     profile_document_delete_blocked
                     profile_document_exported profile_document_imported profile_document_copied
                     profile_controls_bulk_updated
                     profile_control_created profile_control_updated profile_control_deleted
                     profile_document_published
                     profile_document_submitted_for_review profile_document_approved profile_document_rejected
                     profile_document_baseline_declared],
    "Control Catalogs" => %w[control_catalog_created control_catalog_updated control_catalog_deleted
                             control_catalog_delete_blocked
                             control_catalog_exported control_catalog_imported
                             control_family_created control_family_updated control_family_deleted
                             catalog_control_created catalog_control_updated catalog_control_deleted
                             catalog_control_baseline_updated catalog_control_baselines_bulk_updated
                             control_catalog_published
                             control_catalog_submitted_for_review control_catalog_approved control_catalog_rejected],
    "Control Mappings" => %w[control_mapping_created control_mapping_updated control_mapping_deleted
                             control_mapping_exported control_mapping_published
                             control_mapping_deprecated mapping_entry_created mapping_entry_deleted
                             mapping_entry_updated
                             api_mapping_entry_created api_mapping_entry_updated api_mapping_entry_deleted
                             converter_refresh_started],
    "Evidence" => %w[evidence_created evidence_updated evidence_deleted
                     evidence_upload_rejected incomplete_evidence_reported
                     attestation_created attestation_deleted
                     evidence_control_link_created evidence_control_link_deleted],
    "Authorization Boundaries" => %w[authorization_boundary_created authorization_boundary_updated
                                     authorization_boundary_deleted authorization_boundary_delete_blocked
                                     project_created project_updated
                                     project_deleted boundary_created boundary_updated boundary_deleted
                                     ato_package_created ato_package_exported],
    "Organizations" => %w[organization_created organization_updated organization_deactivated
                          organization_reactivated organization_member_added organization_member_removed
                          organization_boundary_assigned],
    "Service Accounts" => %w[service_account_created service_account_updated service_account_disabled
                             service_account_enabled service_account_deleted
                             service_account_token_regenerated service_account_auto_disabled],
    "Translations" => %w[translation_hdf_to_oscal_sar translation_hdf_to_oscal_poam
                         translation_hdf_amendments_to_oscal_poam
                         translation_oscal_poam_to_hdf_amendments],
    "API Tokens" => %w[api_token_created api_token_revoked],
    "Back Matter" => %w[back_matter_resource_created back_matter_resource_updated
                        back_matter_resource_deleted back_matter_resource_linked
                        back_matter_resource_unlinked back_matter_resource_archived
                        back_matter_resource_restored
                        back_matter_resource_promotion_requested
                        back_matter_resource_promotion_approved
                        back_matter_resource_promotion_rejected
                        back_matter_resources_bulk_imported],
    "Converters" => %w[converter_created converter_updated converter_deleted
                       converter_imported converter_exported
                       converter_entry_created converter_entry_deleted
                       stig_imported],
    "Federation" => %w[federation_peer_created federation_peer_updated
                       federation_peer_deleted federation_peer_synced],
    "Findings & Scanning" => %w[finding_disposition_set finding_disposition_cleared
                                finding_disposition_approved finding_disposition_rejected
                                scan_run_ingested
                                hdf_aggregation_enqueued hdf_aggregation_run
                                hdf_amendments_exported hdf_package_exported],
    "KSI Validations" => %w[ksi_validation_created ksi_validation_updated
                            ksi_validation_deleted],
    "Data Migrations" => %w[data_migration_completed],
    "Authoritative Sources" => %w[authoritative_source_created
                                  authoritative_sources_import authoritative_sources_export]
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
    ACTION_CATEGORIES.find { |_cat, actions| actions.include?(action) }&.first || "Other"
  end

  # ── Factory ────────────────────────────────────────────────────────────

  # Convenience factory for logging events throughout the app.
  #
  #   AuditEvent.log(user: current_user, action: "login_success",
  #                  provider: "local", ip_address: request.remote_ip,
  #                  subject: @ssp_document)
  #
  # CodeQL `rb/clear-text-storage-sensitive-data` (alert #24) flags the
  # `create!` below, tracing `metadata` back to the PIV login path. The taint
  # source is `PivSessionsController#cert_diagnostics`, which records the SHAPE
  # of the client-certificate header only — byte length and four booleans — and
  # never the certificate or any part of it. See the comment there, which is
  # the authoritative one: the audit log is widely readable and a PIV cert
  # carries the holder's identity.
  #
  # `metadata` IS a general-purpose bag written from many call sites, so this
  # verdict covers the paths that exist today rather than the type. Anything
  # added here that carries credential material would make the alert correct.
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
