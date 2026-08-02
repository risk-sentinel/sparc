# Legacy membership model for authorization boundaries.
# Role list is configurable via SPARC_AUTH_BOUNDARY_ROLES env var.
#
# Note: The system is transitioning to UserRole + Role for boundary
# memberships. This model supports legacy memberships with string roles.
#
# NIST 800-53 Controls:
#   AC-2 Account Management (role assignment within a boundary)
#   AC-3 Access Enforcement (#875 — the configured role vocabulary is resolved
#        to canonical values and validated against the built-ins plus whatever
#        is configured, so equivalent spellings cannot become two look-alike
#        grants and narrowing the list cannot invalidate an existing assignment)
#   CM-6 Configuration Settings (SPARC_AUTH_BOUNDARY_ROLES; reported at boot by
#        config/initializers/zz_role_config_posture.rb)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class AuthorizationBoundaryMembership < ApplicationRecord
  belongs_to :authorization_boundary
  belongs_to :user, optional: true

  # Default roles (used when SPARC_AUTH_BOUNDARY_ROLES is not set)
  DEFAULT_ROLES = %w[
    authorizing_official
    system_owner
    ciso
    isso
    project_member
    assessor
    view_only
  ].freeze

  # Backward compatibility
  ROLES = DEFAULT_ROLES

  DEFAULT_ROLE_LABELS = {
    "authorizing_official" => "Authorizing Official (AO)",
    "system_owner"         => "System Owner (SO/ISO)",
    "ciso"                 => "CISO",
    "isso"                 => "ISSO",
    "project_member"       => "Team Member",
    "assessor"             => "Assessor / 3PAO",
    "view_only"            => "View Only"
  }.freeze

  # ── Role resolution (#875) ────────────────────────────────────────────────
  #
  # `role` was an enum pinned to DEFAULT_ROLES, so SPARC_AUTH_BOUNDARY_ROLES
  # could only ever SUBSET the seven built-ins. Configuring anything else — a
  # custom role, or the human labels our own .env.example shipped — produced an
  # `ArgumentError` the moment the form was submitted: a 500 on Add Member.
  #
  # The enum is gone in favour of an inclusion validation, matching
  # OrganizationMembership, which has accepted configured roles all along. The
  # column is a plain string and nothing used the enum's generated predicates or
  # scopes, so this needs no migration — and because the enum enforced keys for
  # the whole life of the table, every existing row already holds one.
  #
  # Resolution follows the same discipline as ControlId (app/models/control_id.rb):
  # normalize FORM mechanically, and keep VOCABULARY in an explicit table.
  # `ISSO` -> `isso` is form. `AO` -> `authorizing_official` is vocabulary, and
  # no amount of case-folding gets there — a table has to say so. Anything that
  # matches neither is a genuine custom role and is kept, not "corrected".

  # Form only: case, separators, punctuation. Never vocabulary.
  def self.normalize_role(raw)
    raw.to_s.strip.downcase.gsub(/[^[:alnum:]]+/, "_").gsub(/\A_+|_+\z/, "")
  end

  # Abbreviations that appear in no label verbatim, plus the "System Owner (SO)"
  # spelling our own .env.example shipped (the real label is "(SO/ISO)", which
  # normalizes differently). Deliberately NOT included: `owner` and `viewer` from
  # the old docs example — too loose a guess to collapse a role on.
  ROLE_ALIASES = {
    "ao"              => "authorizing_official",
    "so"              => "system_owner",
    "iso"             => "system_owner",
    "system_owner_so" => "system_owner",
    "3pao"            => "assessor"
  }.freeze

  # Derived from the labels rather than hand-maintained, so relabelling a role
  # cannot silently orphan its alias. Covers "Authorizing Official (AO)",
  # "Team Member" -> project_member, "Assessor / 3PAO" -> assessor, etc.
  LABEL_ALIASES = DEFAULT_ROLE_LABELS.each_with_object({}) do |(key, label), map|
    map[normalize_role(label)] = key
  end.freeze

  # Configured entry -> stored role value.
  def self.resolve_role(raw)
    normalized = normalize_role(raw)
    return normalized if DEFAULT_ROLES.include?(normalized)

    ROLE_ALIASES[normalized] || LABEL_ALIASES[normalized] || normalized
  end

  before_validation :canonicalize_role

  validates :user_name, presence: true
  validates :role, presence: true
  # Guarded by `role_changed?` so retiring a role from the configuration never
  # strands the rows that already hold it. Without the guard, removing a custom
  # role would make every existing member holding it unsaveable — including via
  # `link_to_user!` below, which updates an unrelated column.
  validates :role,
            inclusion: { in: ->(record) { record.class.acceptable_roles }, message: "is not an available role" },
            if: -> { role.present? && role_changed? }

  # Configured entries, resolved. `[{ value:, label: }]`; label is nil unless the
  # operator supplied one via the "role:Label" form.
  def self.configured_roles
    SparcConfig.auth_boundary_role_entries
               .map { |entry| { value: resolve_role(entry[:raw]), label: entry[:label] } }
               .uniq { |entry| entry[:value] }
  end

  # What the Add Member dropdown offers. The configured list REPLACES the
  # defaults, so subsetting still works; unset falls back to all seven.
  def self.available_roles
    configured_roles.map { |entry| entry[:value] }.presence || DEFAULT_ROLES
  end

  # What the model will accept. Always a superset of the defaults, so a value
  # that was valid yesterday cannot become invalid because the dropdown changed.
  def self.acceptable_roles
    (DEFAULT_ROLES + available_roles).uniq
  end

  # Returns role options for select dropdowns: [[label, value], ...]
  def self.role_options
    available_roles.map { |r| [ role_label_for(r), r ] }
  end

  # Human-readable label for any role. An operator-supplied "role:Label" wins,
  # then the built-in labels, then titleize as a last resort.
  def self.role_label_for(role)
    key = role.to_s
    configured_labels[key] || DEFAULT_ROLE_LABELS[key] || key.titleize
  end

  def self.configured_labels
    configured_roles.each_with_object({}) do |entry, map|
      map[entry[:value]] = entry[:label] if entry[:label].present?
    end
  end

  # Instance method for convenience
  def role_label
    self.class.role_label_for(role)
  end

  # Link this legacy membership to a User record by matching email.
  # Returns true if linked, false if no matching user found.
  def link_to_user!
    return true if user_id.present?

    matched_user = User.find_by("LOWER(email) = ?", user_email.to_s.downcase.strip)
    if matched_user
      update!(user_id: matched_user.id)
      true
    else
      false
    end
  end

  private

  # Store the resolved value, so "ISSO" and "isso" are one role rather than two
  # rows that only look alike. Only on change — an existing row is left exactly
  # as it was persisted.
  def canonicalize_role
    return if role.blank? || !role_changed?

    self.role = self.class.resolve_role(role)
  end
end
