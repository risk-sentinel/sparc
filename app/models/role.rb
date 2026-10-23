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
  #
  # NOTE: this is a %w[] array — do NOT put comments inside it. Each line becomes
  # an element, so a comment silently adds junk keys rather than being ignored.
  #
  # #919 removed `converters.read`. Any authenticated user may read converters, so
  # the absence of a check is correct behaviour and the key was redundant: it was
  # granted to 7 roles and enforced by no code, which advertises an access boundary
  # that does not exist. A permission that grants nothing is worse than no
  # permission, because the role catalog implies a restriction a reader will trust.
  # Entries left in stored `roles.permissions` JSONB become inert.
  #
  # `catalogs.read`, `profiles.read` and `mappings.read` went the same way, for
  # the same reason (owner, 2026-10-22). Reading the control library is governed
  # by sign-in, or by nothing when SPARC_PUBLIC_CATALOGS=true
  # (Authentication#public_controls_read), and through the API by any valid
  # token. No code ever consulted the three keys; the old discovery listing was
  # the only thing that read them, so a role without them still read every
  # catalog, profile and mapping.
  # #1044 — `admin.administer` is instance-administrator AUTHORITY, grantable
  # from an IdP so an operator can hold it for a bounded window rather than
  # permanently. It sits in the `admin` namespace, already labelled "Instance
  # Administration", rather than the `instance.administer` the issue proposed —
  # that would have opened a second group meaning the same thing as the one that
  # exists.
  #
  # AUTHORITY, never IDENTITY. `users.admin` remains the dedicated break-glass
  # account: unreachable from any claim by construction (IdpGrantResolver only
  # ever produces user_roles and organization_memberships), and still the only
  # thing the separation-of-duties carve-outs accept.
  PERMISSION_KEYS = %w[
    catalogs.write
    catalogs.approve
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
    cdef.scope_instance
    evidence.read
    evidence.write
    evidence.attest
    mappings.write
    converters.write
    back_matter.read
    back_matter.write
    back_matter.promote
    back_matter.approve_promotion
    back_matter.archive
    back_matter.bulk_import
    back_matter.federate
    amendment.approve
    admin.rotate_credentials
    admin.administer
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
    "amendment" => "HDF Amendments",
    "admin" => "Instance Administration"
  }.freeze

  # Check if this role has a specific permission
  def has_permission?(key)
    permissions[key] == true
  end

  # Bulk-set permissions from form params ({ "ssp.read" => "1", ... })
  # Accepts the web form's "1"/absent convention AND real booleans, so the API
  # (#1014) can send `{"ssp.read": true}` — the natural JSON shape — while
  # the checkbox params the UI submits keep behaving exactly as before. An
  # unchecked box is absent, casts to nil, and lands as false either way.
  def assign_permissions(perm_params)
    caster = ActiveModel::Type::Boolean.new
    self.permissions = PERMISSION_KEYS.each_with_object({}) do |key, hash|
      hash[key] = caster.cast(perm_params[key]) || false
    end
  end

  # ── Shipped defaults vs administrator overrides (#1259) ──────────────────
  #
  # A built-in role (BuiltInRoles) has a shipped default for every permission
  # key and for each of BuiltInRoles::ATTRIBUTES. `admin_overrides` records the
  # ones an instance administrator has set to something else, as
  # `{ key => the shipped default when the choice was recorded }`. The roles
  # seed section never changes a key recorded there (BuiltInRoleSeeder), and
  # the shipped default stored with it is how the seeds tell a shipped change
  # they are now skipping from one they already reported.
  #
  # NIST 800-53: AC-2, AC-3, AC-6, CM-6.

  def built_in? = BuiltInRoles.built_in?(name)

  # This role's shipped default for a permission key or attribute; nil for a
  # role an administrator created.
  def shipped_default(key) = BuiltInRoles.default_for(name, key)

  # The role's current value for a permission key or attribute, in the form it
  # is compared to the shipped default.
  def current_value(key)
    key = key.to_s
    return permissions.to_h[key] == true unless BuiltInRoles::ATTRIBUTES.include?(key)

    self.class.comparable(key, public_send(key))
  end

  def differs_from_default?(key)
    built_in? && current_value(key) != self.class.comparable(key, shipped_default(key))
  end

  def admin_overridden?(key) = admin_overrides.to_h.key?(key.to_s)

  # Called by the role editor and the API after an administrator's values are
  # assigned, with the keys that request set. Each one that now differs from
  # the shipped default is recorded as the administrator's choice; each one
  # that matches it (a reset to default included) is released, so it follows
  # the shipped default again. A role that is not built in has no defaults, so
  # nothing differs from one and nothing is recorded.
  def record_admin_choices(keys)
    overrides = admin_overrides.to_h.dup
    keys.map(&:to_s).each do |key|
      if differs_from_default?(key)
        overrides[key] = self.class.comparable(key, shipped_default(key))
      else
        overrides.delete(key)
      end
    end
    self.admin_overrides = overrides
  end

  # The keys an edit request set: every permission key when it carried a
  # permission map (the map is a complete statement of the role's rights), and
  # each attribute it named.
  def self.edited_keys(attribute_params, permissions_assigned:)
    attrs = BuiltInRoles::ATTRIBUTES & attribute_params.to_h.keys.map(&:to_s)
    permissions_assigned ? PERMISSION_KEYS + attrs : attrs
  end

  # A blank description and none at all are the same statement, and a form
  # submits sort order as a string.
  def self.comparable(key, value)
    case key.to_s
    when "sort_order" then value.to_i
    when *BuiltInRoles::ATTRIBUTES then value.to_s
    else value == true
    end
  end
end
