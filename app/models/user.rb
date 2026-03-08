# frozen_string_literal: true

# User model for SPARC authentication. Supports local password auth
# (has_secure_password), OAuth/OIDC via linked Identities, and LDAP.
#
# Instance Admin is a boolean column — NOT a role. It's a bypass flag
# that grants full access regardless of role assignments.
#
# Email normalization: all emails are downcased and stripped before
# validation to prevent case-sensitivity issues across auth providers
# (e.g., jane.doe@aol.com == Jane.Doe@AOL.com).
class User < ApplicationRecord
  # Allow password_digest to be null for OIDC-only users
  has_secure_password validations: false

  has_many :identities, dependent: :destroy
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :audit_events, dependent: :nullify

  # ── Validations ─────────────────────────────────────────────────────────
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  # Password validations only when a password is being set
  validates :password, length: { minimum: 12, message: "must be at least 12 characters (NIST 800-63B)" },
                       confirmation: true,
                       allow_nil: true

  validates :password_confirmation, presence: { message: "can't be blank" },
                                    if: -> { password.present? }

  validates :status, inclusion: { in: %w[active suspended deactivated] }

  # ── Callbacks ───────────────────────────────────────────────────────────
  before_validation :normalize_email

  # ── Scopes ──────────────────────────────────────────────────────────────
  scope :active, -> { where(status: "active") }
  scope :admins, -> { where(admin: true) }

  # ── Status helpers ──────────────────────────────────────────────────────

  def active?    = status == "active"
  def suspended? = status == "suspended"

  # ── Role helpers ────────────────────────────────────────────────────────

  # Check if user has a given role (by name) optionally scoped to a project.
  # Instance Admin bypasses all role checks.
  #
  #   user.has_role?("isso")                # instance-level
  #   user.has_role?("isso", project_id: 5) # project-level
  def has_role?(role_name, project_id: nil)
    return true if admin?

    scope = user_roles.joins(:role).where(roles: { name: role_name })
    scope = scope.where(project_id: project_id) if project_id
    scope.exists?
  end

  # All role names for this user (optionally project-scoped)
  def role_names(project_id: nil)
    scope = user_roles.joins(:role)
    scope = scope.where(project_id: project_id) if project_id
    scope.pluck("roles.name")
  end

  # ── Permission helpers ─────────────────────────────────────────────

  # Check if user has a specific granular permission, optionally scoped
  # to a project. Instance Admin bypasses all permission checks.
  #
  #   user.has_permission?("ssp.write")
  #   user.has_permission?("ssp.write", project_id: 5)
  def has_permission?(permission_key, project_id: nil)
    return true if admin?

    role_scope = user_roles.joins(:role)
    role_scope = if project_id
      role_scope.where(project_id: [ project_id, nil ])
    else
      role_scope.where(project_id: nil)
    end

    role_scope.where("roles.permissions @> ?", { permission_key => true }.to_json).exists?
  end

  # ── Display ─────────────────────────────────────────────────────────────

  def display_label
    display_name.presence || [ first_name, last_name ].compact_blank.join(" ").presence || email
  end

  # ── Sign-in tracking ───────────────────────────────────────────────────

  def record_sign_in!(ip_address: nil)
    update!(
      last_sign_in_at: Time.current,
      last_sign_in_ip: ip_address,
      sign_in_count: sign_in_count + 1
    )
  end

  private

  def normalize_email
    self.email = email.to_s.downcase.strip if email.present?
  end
end
