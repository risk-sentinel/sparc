# frozen_string_literal: true

# #1259 — the SHIPPED DEFAULTS of every built-in role: one definition that the
# roles seed section, the role editor (web and API) and the upgrade all read.
#
# These used to be top-level constants inside the `roles` section of
# db/seeds.rb, which the running application could not load. The seeds were
# therefore the only code that knew what a built-in role's rights were meant
# to be, and they used that knowledge one way: every run of the section
# replaced each built-in role's whole permission hash, discarding whatever an
# instance administrator had granted or revoked in Admin -> Roles or through
# /api/v1/roles. Defined here, the same values tell the editor what differs
# from the default and the seeds what an administrator chose; see
# BuiltInRoleSeeder and Role#record_admin_choices.
#
# A shipped default is a statement about a NEW install and about any key an
# administrator has not set. It is never a reason to undo an administrator's
# choice.
#
# NIST 800-53: AC-2 (account management), AC-3 (access enforcement), AC-5
# (separation of duties), AC-6 (least privilege), CM-6 (configuration settings).
module BuiltInRoles
  PERM_ALL_READ = Role::PERMISSION_KEYS.select { |k| k.end_with?(".read") }
                                        .each_with_object({}) { |k, h| h[k] = true }.freeze

  # Permission keys that recur across the role defaults below. Named once so the
  # role hashes reference a constant instead of repeating the literal (ruby:S1192).
  K_AUTHORIZATION_BOUNDARIES_READ = "authorization_boundaries.read"
  K_CDEF_READ                     = "cdef.read"
  K_CDEF_WRITE                    = "cdef.write"
  K_EVIDENCE_READ                 = "evidence.read"
  K_EVIDENCE_WRITE                = "evidence.write"
  # #947 — authority to ASSERT, distinct from the permission to add evidence.
  # An attestation is evidence whose whole substance is who asserted it, so
  # "may upload a file" must not imply "may sign for the system". Which roles
  # hold this is deliberately configuration rather than a hardcoded list, so
  # organizations with different rule sets can express their own.
  K_EVIDENCE_ATTEST               = "evidence.attest"
  K_POAM_READ                     = "poam.read"
  K_POAM_WRITE                    = "poam.write"
  K_SAP_READ                      = "sap.read"
  K_SAP_WRITE                     = "sap.write"
  K_SAR_READ                      = "sar.read"
  K_SAR_WRITE                     = "sar.write"
  K_SSP_READ                      = "ssp.read"
  K_SSP_WRITE                     = "ssp.write"

  # #947 — Policy holds `evidence.attest` so that INSTANCE-WIDE evidence has an
  # authority chain of its own. Boundary-less evidence is provider material —
  # it arrives from a leveraged SSP as inherited/common controls — so it belongs
  # to no single system and no System Owner can speak for it. The model confines
  # an instance-scoped attest grant to exactly that case: it does NOT let Policy
  # sign for an individual boundary's evidence, which remains the accountable
  # boundary roles' job. See Attestation.attestable_roles_for.
  #
  # #1257 — and `cdef.write`. Every CDEF write is checked at instance level
  # (#738/#1032), and every other built-in role holding the key is
  # boundary-scoped, so before this only an instance administrator could create
  # or edit a component definition. An organization-wide CDEF is the kind of
  # enterprise policy artifact this role maintains. Approving one stays with
  # `cdef.approve` / this role, unchanged.
  #
  # Holding it at instance level is also what lets this role make a CDEF
  # instance-wide (CdefScopeService.may_scope_instance?): it curates which
  # component definitions every organization shares, so one vetted CDEF serves
  # them all instead of a copy per organization. Before #1257 only an instance
  # administrator could (#980).
  PERM_POLICY_MANAGER = PERM_ALL_READ.merge(
    "catalogs.write" => true, "profiles.write" => true, "mappings.write" => true,
    K_CDEF_WRITE => true,
    K_EVIDENCE_ATTEST => true
  ).freeze

  # #809 — the Authorizing Official accepts residual risk, so approving an HDF
  # amendment (which suppresses a finding for its validity window) is an AO act.
  PERM_AO = {
    K_AUTHORIZATION_BOUNDARIES_READ => true, K_SSP_READ => true, K_SAR_READ => true,
    K_SAP_READ => true, K_POAM_READ => true, K_POAM_WRITE => true,
    K_CDEF_READ => true, K_EVIDENCE_READ => true,
    K_EVIDENCE_ATTEST => true,
    "amendment.approve" => true
  }.freeze

  PERM_SO_ISO = {
    K_AUTHORIZATION_BOUNDARIES_READ => true, K_SSP_READ => true, K_SSP_WRITE => true,
    K_SAR_READ => true, K_SAP_READ => true, K_POAM_READ => true,
    K_POAM_WRITE => true, K_CDEF_READ => true, K_CDEF_WRITE => true,
    K_EVIDENCE_READ => true, K_EVIDENCE_WRITE => true,
    K_EVIDENCE_ATTEST => true
  }.freeze

  PERM_CISO = {
    K_AUTHORIZATION_BOUNDARIES_READ => true, K_SSP_READ => true,
    K_SAR_READ => true, K_SAP_READ => true,
    K_POAM_READ => true, K_CDEF_READ => true, K_EVIDENCE_READ => true,
    K_EVIDENCE_ATTEST => true
  }.freeze

  PERM_ISSO = {
    K_AUTHORIZATION_BOUNDARIES_READ => true, K_SSP_READ => true, K_SSP_WRITE => true,
    K_SAR_READ => true, K_SAR_WRITE => true,
    K_SAP_READ => true, K_SAP_WRITE => true,
    K_POAM_READ => true, K_POAM_WRITE => true,
    K_CDEF_READ => true, K_EVIDENCE_READ => true, K_EVIDENCE_WRITE => true,
    K_EVIDENCE_ATTEST => true
  }.freeze

  PERM_TEAM_MEMBER = {
    K_AUTHORIZATION_BOUNDARIES_READ => true,
    K_SSP_READ => true, K_SSP_WRITE => true,
    K_POAM_READ => true, K_POAM_WRITE => true,
    K_CDEF_READ => true, K_CDEF_WRITE => true,
    K_EVIDENCE_READ => true, K_EVIDENCE_WRITE => true
  }.freeze

  PERM_ASSESSOR = {
    K_AUTHORIZATION_BOUNDARIES_READ => true, K_SSP_READ => true,
    K_SAR_READ => true, K_SAR_WRITE => true,
    K_SAP_READ => true, K_SAP_WRITE => true,
    K_POAM_READ => true, K_CDEF_READ => true, K_EVIDENCE_READ => true
  }.freeze

  PERM_VIEW_ONLY = {
    K_AUTHORIZATION_BOUNDARIES_READ => true, K_SSP_READ => true,
    K_SAR_READ => true, K_POAM_READ => true,
    K_CDEF_READ => true, K_EVIDENCE_READ => true
  }.freeze

  # Senior Accountable Official — instance-scoped oversight role.
  #
  # #947 — `evidence.attest` is stripped rather than inherited. `has_permission?`
  # matches `authorization_boundary_id: [id, nil]`, so an INSTANCE-scoped grant
  # satisfies the check on EVERY boundary. Inheriting CISO's attest permission
  # here would hand one oversight role the authority to sign for every system on
  # the instance — estate-wide attestation authority that nobody decided to
  # grant, arriving silently through a `.dup`. Attest authority is deliberately
  # boundary-scoped: it is asserted about a specific system, by someone
  # accountable for that system.
  PERM_SAO = PERM_CISO.except(K_EVIDENCE_ATTEST).freeze

  PERM_COMMON_CONTROL = {
    K_AUTHORIZATION_BOUNDARIES_READ => true, K_SSP_READ => true, K_SSP_WRITE => true,
    K_CDEF_READ => true, K_CDEF_WRITE => true,
    K_EVIDENCE_READ => true, K_EVIDENCE_WRITE => true,
    K_EVIDENCE_ATTEST => true
  }.freeze

  PERM_SAOP = {
    K_AUTHORIZATION_BOUNDARIES_READ => true, K_SSP_READ => true,
    K_SAR_READ => true, K_SAP_READ => true,
    K_POAM_READ => true, K_CDEF_READ => true, K_EVIDENCE_READ => true
  }.freeze

  PERM_SPARC_SME = {
    K_AUTHORIZATION_BOUNDARIES_READ => true,
    K_SSP_READ => true, K_SSP_WRITE => true,
    K_SAR_READ => true, K_SAR_WRITE => true,
    K_SAP_READ => true, K_SAP_WRITE => true,
    K_POAM_READ => true, K_POAM_WRITE => true,
    K_CDEF_READ => true, K_CDEF_WRITE => true,
    K_EVIDENCE_READ => true, K_EVIDENCE_WRITE => true
  }.freeze

  PERM_EVIDENCE_ENGINEER = {
    K_AUTHORIZATION_BOUNDARIES_READ => true,
    K_SSP_READ => true,
    K_SAR_READ => true, K_SAR_WRITE => true,
    K_SAP_READ => true,
    K_POAM_READ => true,
    K_CDEF_READ => true,
    K_EVIDENCE_READ => true, K_EVIDENCE_WRITE => true
  }.freeze

  PERM_CHIEF_ACQUISITION_OFFICER = {
    K_AUTHORIZATION_BOUNDARIES_READ => true,
    K_CDEF_READ => true, K_EVIDENCE_READ => true
  }.freeze

  PERM_ISSM = {
    K_AUTHORIZATION_BOUNDARIES_READ => true,
    K_SSP_READ => true, K_SSP_WRITE => true,
    K_SAR_READ => true, K_SAP_READ => true,
    K_POAM_READ => true, K_POAM_WRITE => true,
    K_CDEF_READ => true,
    K_EVIDENCE_READ => true, K_EVIDENCE_WRITE => true,
    K_EVIDENCE_ATTEST => true,
    "amendment.approve" => true # #809 — ISSM reviews/approves amendments on the AO's behalf
  }.freeze

  PERM_CSP = {
    K_AUTHORIZATION_BOUNDARIES_READ => true,
    K_SSP_READ => true, K_SSP_WRITE => true,
    K_SAR_READ => true, K_SAP_READ => true,
    K_POAM_READ => true, K_POAM_WRITE => true,
    K_CDEF_READ => true, K_CDEF_WRITE => true,
    K_EVIDENCE_READ => true, K_EVIDENCE_WRITE => true
  }.freeze

  PERM_SYSTEM_ARCHITECT = {
    K_AUTHORIZATION_BOUNDARIES_READ => true,
    K_SSP_READ => true, K_SSP_WRITE => true,
    K_CDEF_READ => true, K_CDEF_WRITE => true,
    K_EVIDENCE_READ => true
  }.freeze

  PERM_COMPONENT_SUPPLIER = {
    K_AUTHORIZATION_BOUNDARIES_READ => true,
    K_CDEF_READ => true, K_CDEF_WRITE => true,
    K_EVIDENCE_READ => true, K_EVIDENCE_WRITE => true
  }.freeze

  PERM_SYSTEM_OPERATOR = {
    K_AUTHORIZATION_BOUNDARIES_READ => true,
    K_SSP_READ => true, K_POAM_READ => true,
    K_CDEF_READ => true,
    K_EVIDENCE_READ => true, K_EVIDENCE_WRITE => true
  }.freeze

  PERM_INFO_OWNER = {
    K_AUTHORIZATION_BOUNDARIES_READ => true,
    K_SSP_READ => true, K_CDEF_READ => true,
    K_EVIDENCE_READ => true
  }.freeze

  PERM_SOLUTION_EVALUATOR = {
    K_AUTHORIZATION_BOUNDARIES_READ => true,
    K_SSP_READ => true, K_SAR_READ => true,
    K_CDEF_READ => true, K_EVIDENCE_READ => true
  }.freeze

  PERM_VENDOR_DEPENDENCY = {
    K_AUTHORIZATION_BOUNDARIES_READ => true, K_SSP_READ => true,
    K_CDEF_READ => true, K_CDEF_WRITE => true,
    K_EVIDENCE_READ => true, K_EVIDENCE_WRITE => true
  }.freeze

  # #1044 — instance-administrator authority. `admin.administer` short-circuits
  # User#has_permission?, so this single key carries every capability the
  # break-glass account has. Listing more here would imply the others are doing
  # work; they would be inert.
  PERM_INSTANCE_ADMIN = { "admin.administer" => true }.freeze

  DEFINITIONS = [
    # ── Instance-Scope Roles ──────────────────────────────────────────────────
    # #1044 — the role an IdP grants for a BOUNDED window. Carrying
    # `admin.administer` confers instance-administrator AUTHORITY; it does NOT
    # make the holder the break-glass account (`users.admin`), which no claim can
    # confer or revoke. Name it in SPARC_OIDC_INSTANCE_ROLES to allow the grant,
    # then expire the group membership in the IdP — the next sign-in revokes it.
    { name: "instance_admin", display_name: "Instance Administrator", scope: "instance", sort_order: 0,
      description: "Instance-wide administrative authority, intended to be granted for a bounded window by an identity provider rather than held permanently. Distinct from the dedicated break-glass administrator account, which is never conferred or revoked by a directory and remains the recovery path of last resort.",
      permissions: PERM_INSTANCE_ADMIN },
    { name: "policy_manager", display_name: "Policy Manager", scope: "instance", sort_order: 1,
      description: "Manages organizational security policies, control catalogs, and compliance baselines. Develops, publishes, and maintains tailored profiles and enterprise-wide security policy frameworks aligned with NIST, FedRAMP, and OSCAL standards.",
      permissions: PERM_POLICY_MANAGER },
    { name: "global_viewer", display_name: "Global Viewer", scope: "instance", sort_order: 2,
      description: "Read-only access to shared control catalogs and baseline profiles across the instance. Provides broad visibility into reusable control libraries for stakeholders who need awareness without edit privileges.",
      permissions: PERM_ALL_READ },
    { name: "senior_accountable_official", display_name: "Senior Accountable Official", scope: "instance", sort_order: 3,
      description: "Leads the Risk Executive function for the organization. Aligns security and privacy risk management with strategic planning and mission objectives. Provides enterprise-wide risk oversight and advises on organizational risk tolerance per NIST SP 800-37.",
      permissions: PERM_SAO },
    { name: "senior_agency_official_privacy", display_name: "Senior Agency Official for Privacy", scope: "instance", sort_order: 4,
      description: "Senior Agency Official for Privacy (SAOP). Oversees organization-wide privacy risk management, assesses privacy impacts, manages PII processing requirements, and ensures compliance with privacy controls and regulations.",
      permissions: PERM_SAOP },
    { name: "head_of_agency", display_name: "Head of Agency / CEO", scope: "instance", sort_order: 5,
      description: "Ultimate accountability for risk management decisions and RMF integration across the organization. Ensures security and privacy programs are resourced and aligned with mission objectives per NIST SP 800-37.",
      permissions: PERM_ALL_READ },
    { name: "risk_executive", display_name: "Risk Executive", scope: "instance", sort_order: 6,
      description: "Senior-level risk oversight function that advises on organization-wide risk tolerance, strategy, and acceptable risk levels. Coordinates risk-related activities across the enterprise per NIST SP 800-37.",
      permissions: PERM_ALL_READ },
    { name: "cio", display_name: "Chief Information Officer", scope: "instance", sort_order: 7,
      description: "Oversees the organization's information security program and designates the Senior Agency Information Security Officer. Ensures IT investments integrate security and privacy requirements per FISMA and NIST SP 800-37.",
      permissions: PERM_ALL_READ },
    { name: "chief_acquisition_officer", display_name: "Chief Acquisition Officer", scope: "instance", sort_order: 8,
      description: "Ensures security and privacy requirements are integrated into acquisition processes, contracts, and supply chain management. Reviews component definitions and evidence for procurement decisions.",
      permissions: PERM_CHIEF_ACQUISITION_OFFICER },
    { name: "fedramp_pmo", display_name: "FedRAMP PMO", scope: "instance", sort_order: 9,
      description: "FedRAMP Program Management Office. Oversees the FedRAMP authorization program, provides OSCAL templates and validation tools, reviews cloud service authorization packages, and maintains FedRAMP baselines and guidance.",
      permissions: PERM_ALL_READ },
    { name: "jab", display_name: "Joint Authorization Board", scope: "instance", sort_order: 10,
      description: "Reviews OSCAL-formatted authorization packages for Provisional Authorizations to Operate (P-ATOs) for cloud services intended for government-wide use. Composed of CIOs from DHS, DOD, and GSA.",
      permissions: PERM_ALL_READ },

    # ── Authorization-Boundary-Scope Roles ───────────────────────────────────
    { name: "ao", display_name: "Authorizing Official", scope: "authorization_boundary", sort_order: 11,
      description: "Senior official who accepts residual risk and issues the Authorization to Operate (ATO) decision. Reviews Security Assessment Report (SAR) findings and POA&M remediation progress to make risk-informed authorization decisions per NIST SP 800-37.",
      permissions: PERM_AO },
    { name: "agency_ao", display_name: "Agency Authorizing Official", scope: "authorization_boundary", sort_order: 12,
      description: "Issues agency-specific Authorizations to Operate (ATOs) based on FedRAMP baselines and OSCAL artifacts. Evaluates residual risk within the agency's specific operating context and mission requirements.",
      permissions: PERM_AO },
    { name: "so_iso", display_name: "System Owner / ISO", scope: "authorization_boundary", sort_order: 13,
      description: "Owns the information system and is accountable for its security posture. Responsible for control implementation, SSP development and maintenance, system boundary definition, and coordination with ISSOs and security teams per NIST SP 800-37.",
      permissions: PERM_SO_ISO },
    { name: "ciso", display_name: "CISO", scope: "authorization_boundary", sort_order: 14,
      description: "Senior Agency Information Security Officer (SAISO) / Chief Information Security Officer. Provides strategic security oversight, policy direction, risk advice, and compliance program leadership across the organization per NIST SP 800-37.",
      permissions: PERM_CISO },
    { name: "issm", display_name: "ISSM", scope: "authorization_boundary", sort_order: 15,
      description: "Information System Security Manager. Oversees the system security posture, supports the System Owner, coordinates with ISSOs, and ensures security requirements are implemented and maintained across the system lifecycle per NIST SP 800-37.",
      permissions: PERM_ISSM },
    { name: "isso", display_name: "ISSO", scope: "authorization_boundary", sort_order: 16,
      description: "Information System Security Officer. Day-to-day security operations for the information system. Maintains security controls, coordinates assessment activities, tracks POA&M findings, supports the System Owner, and ensures continuous monitoring compliance per NIST SP 800-37.",
      permissions: PERM_ISSO },
    { name: "cloud_service_provider", display_name: "Cloud Service Provider", scope: "authorization_boundary", sort_order: 17,
      description: "Develops and maintains the OSCAL-formatted System Security Plan (SSP), implements controls, prepares authorization packages, manages POA&Ms, and provides component definitions for cloud service offerings under FedRAMP.",
      permissions: PERM_CSP },
    { name: "assessor_3pao", display_name: "Assessor / 3PAO", scope: "authorization_boundary", sort_order: 18,
      description: "Independent control assessor or Third-Party Assessment Organization (3PAO). Conducts security assessments, develops Security Assessment Plans (SAPs), produces Security Assessment Reports (SARs), and provides objective evaluation of control effectiveness.",
      permissions: PERM_ASSESSOR },
    { name: "common_control_provider", display_name: "Common Control Provider", scope: "authorization_boundary", sort_order: 19,
      description: "Implements, assesses, and monitors common (inherited) controls shared across multiple information systems. Documents common control details and disseminates implementation information for use in system-level SSPs per NIST SP 800-37.",
      permissions: PERM_COMMON_CONTROL },
    { name: "system_architect_engineer", display_name: "System Architect / Engineer", scope: "authorization_boundary", sort_order: 20,
      description: "Designs and implements security architecture and controls. Contributes to SSP technical sections, develops component definitions, and ensures system design meets security requirements and OSCAL documentation standards.",
      permissions: PERM_SYSTEM_ARCHITECT },
    { name: "component_supplier", display_name: "Component Supplier / Product Engineer", scope: "authorization_boundary", sort_order: 21,
      description: "Provides reusable components with documented control implementations for OSCAL Component Definitions. Supplies evidence of component security capabilities and maintains component-level security documentation.",
      permissions: PERM_COMPONENT_SUPPLIER },
    { name: "system_operator_admin", display_name: "System Operator / Administrator", scope: "authorization_boundary", sort_order: 22,
      description: "Performs daily system operations, monitoring, and maintenance. Implements operational controls, collects operational evidence, and supports continuous monitoring activities for the information system.",
      permissions: PERM_SYSTEM_OPERATOR },
    { name: "information_owner_steward", display_name: "Information Owner / Steward", scope: "authorization_boundary", sort_order: 23,
      description: "Defines protection requirements for information types processed by the system. Supports system categorization per FIPS 199, establishes data governance policies, and ensures information handling complies with applicable regulations.",
      permissions: PERM_INFO_OWNER },
    { name: "vendor_dependency_manager", display_name: "Vendor Dependency Manager", scope: "authorization_boundary", sort_order: 24,
      description: "Tracks and documents vendor-supplied components and inherited controls critical for OSCAL Component Definitions. Manages vendor security documentation, supply chain dependencies, and third-party evidence collection.",
      permissions: PERM_VENDOR_DEPENDENCY },
    { name: "solution_evaluator", display_name: "Solution Evaluator", scope: "authorization_boundary", sort_order: 25,
      description: "Assesses tools, solutions, and services for OSCAL compliance and integration readiness. Reviews SSP content, SAR findings, and component definitions to evaluate solution suitability for security requirements.",
      permissions: PERM_SOLUTION_EVALUATOR },
    { name: "project_member", display_name: "Team Member", scope: "authorization_boundary", sort_order: 26,
      description: "General team member who contributes to authorization boundary documentation and artifacts. Can view and edit SSP content, manage POA&Ms, work with component definitions, and collect evidence. Cannot alter global catalogs or baselines.",
      permissions: PERM_TEAM_MEMBER },
    { name: "sparc_sme", display_name: "SPARC SME", scope: "authorization_boundary", sort_order: 27,
      description: "Subject matter expert with broad read/write access to authorization boundary artifacts. Supports multiple artifact types including SSP, SAR, SAP, POA&M, component definitions, and evidence. Read-only access to enterprise catalogs and profiles.",
      permissions: PERM_SPARC_SME },
    { name: "evidence_integration_engineer", display_name: "Evidence Integration Engineer", scope: "authorization_boundary", sort_order: 28,
      description: "Specialized in evidence lifecycle management and assessment integration. Collects, organizes, and links evidence artifacts to control implementations. Supports SAR development with evidence-backed findings and attestations.",
      permissions: PERM_EVIDENCE_ENGINEER },
    { name: "view_only", display_name: "View Only", scope: "authorization_boundary", sort_order: 29,
      description: "Read-only access to assigned authorization boundary artifacts. Intended for auditors, oversight stakeholders, or reviewers who need visibility into SSP, SAR, POA&M, and component documentation without edit capabilities.",
      permissions: PERM_VIEW_ONLY }
  ].freeze

  # ── #919 — grants the seeds were never issuing ────────────────────────────
  #
  # Measured on the 29-role catalog before this change: 11 of the 35 permission
  # keys were enforced by code but granted to NO role. Because User#has_permission?
  # returns true for admins, every one of them was silently instance-admin-only —
  # nobody decided that, it fell out of the seeds. The back_matter cluster was the
  # clearest case: `read` was granted to 7 roles while write/promote/archive/
  # bulk_import/federate/approve_promotion were granted to zero, so the entire
  # back-matter authoring workflow was admin-only out of the box. The same held for
  # catalogs/cdef/profiles `.approve`, which made the #630-#634 approval workflow
  # admin-only too.
  #
  # Applied here rather than by editing thirteen PERM_* constants inline: the grant
  # and the reason it applies to a given role stay in one place, and the role
  # definitions above remain a readable statement of each role's document scope.
  #
  # NIST AC-2 (account management), AC-3 (access enforcement), AC-5 (separation of
  # duties), AC-6 (least privilege).

  # Boundary members manage back-matter that pertains to their boundary.
  #
  # `approve_promotion` and `federate` are deliberately EXCLUDED. Promotion
  # elevates boundary-scoped content to instance-wide authoritative, so the
  # boundary REQUESTS (`promote`) and the instance ADJUDICATES — granting both to
  # the same role would let a member approve their own promotion and defeat the
  # review queue that exists for it (AC-5). Federation is cross-instance and is
  # likewise not a boundary-level act.
  PERM_BACK_MATTER_BOUNDARY = {
    "back_matter.read"        => true,
    "back_matter.write"       => true,
    "back_matter.promote"     => true,
    "back_matter.archive"     => true,
    "back_matter.bulk_import" => true,
    "converters.write"        => true
  }.freeze

  # The policy team owns instance-wide/authoritative back-matter and adjudicates
  # promotion requests coming up from boundaries.
  PERM_BACK_MATTER_INSTANCE = PERM_BACK_MATTER_BOUNDARY.merge(
    "back_matter.approve_promotion" => true,
    "back_matter.federate"          => true,
    "catalogs.approve"              => true,
    "profiles.approve"              => true,
    "cdef.approve"                  => true
  ).freeze

  # The fourteen boundary roles that already hold some document write.
  #
  # Excludes assessor_3pao (separation of duties — an assessor must not edit the
  # provenance it is assessing) and view_only, per the owner's ruling; and also
  # ciso, information_owner_steward and solution_evaluator, which write no document
  # at all today. The governing rule is that the ability to manage back-matter
  # matches the RBAC already decided for documents — nobody gains authority over a
  # compliance artifact that they lack over the document it supports.
  BACK_MATTER_BOUNDARY_ROLES = %w[
    ao agency_ao cloud_service_provider common_control_provider
    component_supplier evidence_integration_engineer issm isso
    project_member so_iso sparc_sme system_architect_engineer
    system_operator_admin vendor_dependency_manager
  ].freeze

  BACK_MATTER_INSTANCE_ROLES = %w[policy_manager].freeze

  # Roster management is DELEGABLE (#919). wiki/RBAC.md already described
  # `manage_members` as "add / remove members and assign roles within a boundary";
  # it was granted to no role and enforced by no code, so the published
  # documentation described a capability the application did not implement. Seeding
  # it here — and enforcing it on both surfaces — makes the documentation true
  # rather than correcting it downward.
  ROSTER_MANAGER_ROLES = %w[issm isso so_iso].freeze
  PERM_ROSTER_MANAGER = {
    "authorization_boundaries.write"          => true,
    "authorization_boundaries.manage_members" => true
  }.freeze

  # CDEF approval is not purely a boundary concern, so the policy team holds it
  # alongside the boundary security leads.
  CDEF_APPROVER_ROLES = %w[issm isso so_iso].freeze

  # Role attributes an administrator may change and the seeds otherwise keep
  # current. `name` is the identity the seeds find a role by, so it is not one
  # of them.
  ATTRIBUTES = %w[display_name description sort_order scope].freeze

  # Each built-in role's complete shipped definition: the attributes above plus
  # `permissions`, a hash of every Role::PERMISSION_KEYS entry to true/false.
  # Composed once, from DEFINITIONS and the cross-cutting grants that follow it.
  def self.all
    @all ||= DEFINITIONS.to_h { |attrs| [ attrs[:name], compose(attrs) ] }.freeze
  end

  def self.names = all.keys

  def self.built_in?(name) = all.key?(name.to_s)

  # The shipped definition of one role, or nil for a role an administrator
  # created.
  def self.definition(name) = all[name.to_s]

  # The shipped default of one permission key or attribute for a role. Nil when
  # the role is not built in.
  def self.default_for(name, key)
    definition = definition(name)
    return nil unless definition

    key = key.to_s
    if ATTRIBUTES.include?(key)
      definition[key.to_sym]
    else
      definition[:permissions][key] == true
    end
  end

  def self.compose(attrs)
    granted = attrs[:permissions].dup
    granted.merge!(PERM_BACK_MATTER_BOUNDARY) if BACK_MATTER_BOUNDARY_ROLES.include?(attrs[:name])
    granted.merge!(PERM_BACK_MATTER_INSTANCE) if BACK_MATTER_INSTANCE_ROLES.include?(attrs[:name])
    granted.merge!(PERM_ROSTER_MANAGER)       if ROSTER_MANAGER_ROLES.include?(attrs[:name])
    granted["cdef.approve"] = true            if CDEF_APPROVER_ROLES.include?(attrs[:name])

    attrs.slice(:name, :display_name, :scope, :sort_order, :description).merge(
      permissions: Role::PERMISSION_KEYS.to_h { |key| [ key, granted[key] == true ] }.freeze
    ).freeze
  end
  private_class_method :compose
end
