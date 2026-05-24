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
#
# NIST 800-53 Controls:
#   AC-2 Account Management (status lifecycle, deactivate!/reactivate!, service account ownership)
#   IA-4 Identifier Management (unique email, case-insensitive, sparc_sa_ prefix)
#   IA-5 Authenticator Management (bcrypt, 12-char min, password expiry)
#   AC-6 Least Privilege (service accounts cannot be admin)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class User < ApplicationRecord
  # Allow password_digest to be null for OIDC-only users
  has_secure_password validations: false

  include AttachmentSizeLimit
  has_one_attached :avatar
  limit_attachment_size :avatar, max: -> { SparcConfig.max_avatar_bytes }

  has_many :identities, dependent: :destroy
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :authorization_boundaries, -> { distinct }, through: :user_roles
  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships
  has_many :audit_events, dependent: :nullify
  has_many :api_tokens, dependent: :destroy

  # Service account ownership — every service account has a human owner
  belongs_to :owner, class_name: "User", optional: true
  has_many :owned_service_accounts, class_name: "User", foreign_key: :owner_id, dependent: :nullify, inverse_of: :owner

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

  # AC-2: Service accounts must have a human owner
  validates :owner_id, presence: { message: "is required for service accounts" }, if: :service_account?

  # SI-10: Avatar file validation — magic-byte type check (no client-supplied
  # Content-Type trust per #509). Size cap handled by AttachmentSizeLimit
  # (above), which honors SPARC_MAX_AVATAR_MB.
  #
  # The controller layer (ProfilesController#update_avatar) is the primary
  # gate — it runs Marcel against the tempfile BEFORE attach. This model
  # validator is defense-in-depth for non-controller paths (API, console,
  # direct ActiveRecord usage). When the blob hasn't yet been persisted to
  # the storage service (validators run before save), there's nothing to
  # sniff; we skip — the controller layer already validated, or the bytes
  # will be re-validated on the next save once the blob is in the service.
  ALLOWED_AVATAR_MIME_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  validate :avatar_image_type, if: -> { avatar.attached? }

  def avatar_image_type
    actual = avatar.blob.open { |io| Marcel::MimeType.for(io) }
    return if ALLOWED_AVATAR_MIME_TYPES.include?(actual)

    errors.add(:avatar, "must be a PNG, JPG, GIF, or WebP image (detected #{actual.inspect})")
  rescue Errno::ENOENT, ActiveStorage::FileNotFoundError
    # Blob not yet persisted to the storage service; controller layer is
    # the primary gate. Skip; will re-validate on the next save once the
    # blob is in the service.
    nil
  end

  # ── Callbacks ───────────────────────────────────────────────────────────
  before_validation :normalize_email
  before_update :enforce_uuid_immutability

  # ── Scopes ──────────────────────────────────────────────────────────────
  scope :active, -> { where(status: "active") }
  scope :admins, -> { where(admin: true) }
  scope :service_accounts, -> { where(service_account: true) }
  scope :human_users, -> { where(service_account: false) }

  # Users who have been active longer than `days` without signing in.
  # Includes users who have never signed in (uses created_at as fallback).
  scope :inactive_past_threshold, ->(days) {
    cutoff = days.days.ago
    active.where(
      "last_sign_in_at < :cutoff OR (last_sign_in_at IS NULL AND created_at < :cutoff)",
      cutoff: cutoff
    )
  }

  # ── Status helpers ──────────────────────────────────────────────────────

  def active?      = status == "active"
  def suspended?   = status == "suspended"
  def deactivated? = status == "deactivated"

  # Soft-delete: set status to deactivated with timestamp and reason.
  def deactivate!(reason: "admin_action")
    update!(status: "deactivated", deleted_at: Time.current, inactive_reason: reason)
  end

  # Restore a deactivated (or suspended) user to active status.
  def reactivate!(force_password_reset: false)
    attrs = { status: "active", deleted_at: nil, inactive_reason: nil }
    attrs[:must_reset_password] = true if force_password_reset
    update!(attrs)
  end

  # ── Service account lifecycle ─────────────────────────────────────────────

  # Disable a service account with a reason (AC-2)
  def disable!(reason: "admin_action")
    update!(disabled_at: Time.current, disabled_reason: reason, status: "suspended")
  end

  # Re-enable a disabled service account (AC-2)
  def enable!
    update!(disabled_at: nil, disabled_reason: nil, status: "active")
  end

  def disabled?
    disabled_at.present?
  end

  # ── Password expiry ──────────────────────────────────────────────────────

  # Returns true when a local-auth user's password is older than the
  # configured expiry threshold. OAuth/SSO-only users are exempt.
  def password_expired?
    return false unless password_digest.present? # OAuth-only users have no password
    return false if identities.exists?           # Users with linked providers are exempt
    return false if password_changed_at.blank?   # No timestamp — treat as not expired

    password_changed_at < SparcConfig.password_expiry_days.days.ago
  end

  # ── Role helpers ────────────────────────────────────────────────────────

  # Check if user has a given role (by name) optionally scoped to an
  # authorization boundary. Instance Admin bypasses all role checks.
  #
  #   user.has_role?("isso")                              # instance-level
  #   user.has_role?("isso", authorization_boundary_id: 5) # boundary-level
  def has_role?(role_name, authorization_boundary_id: nil)
    return true if admin?

    scope = user_roles.joins(:role).where(roles: { name: role_name })
    scope = scope.where(authorization_boundary_id: authorization_boundary_id) if authorization_boundary_id
    scope.exists?
  end

  # All role names for this user (optionally authorization boundary-scoped)
  def role_names(authorization_boundary_id: nil)
    scope = user_roles.joins(:role)
    scope = scope.where(authorization_boundary_id: authorization_boundary_id) if authorization_boundary_id
    scope.pluck("roles.name")
  end

  # ── Permission helpers ─────────────────────────────────────────────

  # Check if user has a specific granular permission, optionally scoped
  # to an authorization boundary. Instance Admin bypasses all permission checks.
  #
  #   user.has_permission?("ssp.write")
  #   user.has_permission?("ssp.write", authorization_boundary_id: 5)
  def has_permission?(permission_key, authorization_boundary_id: nil)
    return true if admin?

    role_scope = user_roles.joins(:role)
    role_scope = if authorization_boundary_id
      role_scope.where(authorization_boundary_id: [ authorization_boundary_id, nil ])
    else
      role_scope.where(authorization_boundary_id: nil)
    end

    role_scope.where("roles.permissions @> ?", { permission_key => true }.to_json).exists?
  end

  # Check if the user has a permission in ANY boundary (or instance-level).
  # Used by the discovery endpoint to determine general capability.
  def has_any_permission?(permission_key)
    return true if admin?

    user_roles.joins(:role)
              .where("roles.permissions @> ?", { permission_key => true }.to_json)
              .exists?
  end

  # ── Display ─────────────────────────────────────────────────────────────

  def display_label
    display_name.presence || [ first_name, last_name ].compact_blank.join(" ").presence || email
  end

  def initials
    parts = [ first_name, last_name ].compact_blank
    if parts.any?
      parts.map { |p| p[0] }.join.upcase[0, 2]
    else
      email[0, 2].upcase
    end
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

  # UUID is immutable once set — prevent accidental overwrites.
  def enforce_uuid_immutability
    self.uuid = uuid_was if uuid_changed? && uuid_was.present?
  end
end
