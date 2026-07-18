# frozen_string_literal: true

# Defines the available roles in SPARC. Roles are either instance-scoped
# (global) or authorization boundary-scoped. Instance Admin is NOT a role —
# it's the users.admin boolean column.
#
# Seeded roles are documented in the RBAC wiki page (wiki/RBAC.md):
#   Instance (10): policy_manager, global_viewer, senior_accountable_official,
#                  senior_agency_official_privacy, head_of_agency, risk_executive,
#                  cio, chief_acquisition_officer, fedramp_pmo, jab
#   Authorization Boundary (19): ao, agency_ao, so_iso, ciso, issm, isso,
#                  cloud_service_provider, assessor_3pao, common_control_provider,
#                  system_architect_engineer, component_supplier, system_operator_admin,
#                  information_owner_steward, vendor_dependency_manager,
#                  solution_evaluator, project_member, sparc_sme,
#                  evidence_integration_engineer, view_only
#
# Permissions are stored as a JSONB hash of "resource.action" => boolean keys.
class Role < ApplicationRecord
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  validates :name, presence: true, uniqueness: true
  validates :display_name, presence: true
  validates :scope, inclusion: { in: %w[instance authorization_boundary] }

  scope :instance_scoped, -> { where(scope: "instance") }
  scope :authorization_boundary_scoped, -> { where(scope: "authorization_boundary") }
  scope :sorted, -> { order(:sort_order) }

  # ── Permissions ──────────────────────────────────────────────────────────
  # Canonical list of all permission keys. Each is "resource.action".
  PERMISSION_KEYS = %w[
    catalogs.read
    catalogs.write
    catalogs.approve
    profiles.read
    profiles.write
    profiles.approve
    authorization_boundaries.read
    authorization_boundaries.write
    authorization_boundaries.manage_members
    ssp.read
    ssp.write
    sar.read
    sar.write
    sap.read
    sap.write
    poam.read
    poam.write
    cdef.read
    cdef.write
    cdef.approve
    evidence.read
    evidence.write
    mappings.read
    mappings.write
    converters.read
    converters.write
    back_matter.read
    back_matter.write
    back_matter.promote
    back_matter.approve_promotion
    back_matter.archive
    back_matter.bulk_import
    back_matter.federate
    admin.rotate_credentials
  ].freeze

  # Group permission keys by resource for UI rendering
  PERMISSION_GROUPS = PERMISSION_KEYS.group_by { |k| k.split(".").first }.freeze

  # Human-readable labels for resource groups
  RESOURCE_LABELS = {
    "catalogs" => "Control Catalogs",
    "profiles" => "Baselines / Profiles",
    "authorization_boundaries" => "Authorization Boundaries",
    "ssp"      => "System Security Plans",
    "sar"      => "Security Assessment Results",
    "sap"      => "Security Assessment Plans",
    "poam"     => "POA&Ms",
    "cdef"     => "Component Definitions",
    "evidence" => "Evidence",
    "mappings" => "Control Mappings",
    "converters" => "Converters",
    "back_matter" => "Back-Matter Resources",
    "admin" => "Instance Administration"
  }.freeze

  # Check if this role has a specific permission
  def has_permission?(key)
    permissions[key] == true
  end

  # Bulk-set permissions from form params ({ "catalogs.read" => "1", ... })
  def assign_permissions(perm_params)
    self.permissions = PERMISSION_KEYS.each_with_object({}) do |key, hash|
      hash[key] = perm_params[key] == "1"
    end
  end
end
