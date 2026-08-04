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
#   AC-2(3) Disable Accounts (inactive_past_threshold sweep; break-glass and
#           last-active-admin are exempt so availability of administration survives it — #878)
#   IA-4 Identifier Management (unique email, case-insensitive, sparc_sa_ prefix)
#   IA-5 Authenticator Management (bcrypt, 12-char min, password expiry)
#   IA-5(1) Password-Based Authentication (SPARC-issued temporary at provisioning,
#           must_reset_password forces replacement at first sign-in — #877)
#   AC-6 Least Privilege (service accounts cannot be admin)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class User < ApplicationRecord
  # Lifecycle statuses (AC-2). Single source of truth for the inclusion
  # validation and for privilege-safe status assignment in
  # UserProvisioningService.
  STATUSES = %w[active suspended deactivated].freeze

  # Allow password_digest to be null for OIDC-only users
  has_secure_password validations: false

  include AttachmentSizeLimit
  has_one_attached :avatar
  limit_attachment_size :avatar, max: -> { SparcConfig.max_avatar_bytes }

  has_many :identities, dependent: :destroy
  has_many :webauthn_credentials, dependent: :destroy   # FIDO2 security keys (#779)
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
  # IA-4: email is the canonical identifier. normalize_email (below) downcases
  # it and `case_sensitive: false` gives a friendly error on duplicates, but
  # the DATABASE is the real guarantee: a functional unique index on
  # LOWER(email) (migration 20260529000000, #593) rejects case-variant
  # duplicates even under races or callback-bypassing writes — closing the
  # "log in as Jane.Doe@x.com vs jane.doe@x.com" workaround when both local
  # login and OIDC are enabled.
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  # Password validations only when a password is being set
  validates :password, length: { minimum: 12, message: "must be at least 12 characters (NIST 800-63B)" },
                       confirmation: true,
                       allow_nil: true

  validates :password_confirmation, presence: { message: "can't be blank" },
                                    if: -> { password.present? }

  validates :status, inclusion: { in: STATUSES }

  # AC-2: Service accounts must have a human owner
  validates :owner_id, presence: { message: "is required for service accounts" }, if: :service_account?

  # SI-10: Avatar file validation — magic-byte type check (no client-supplied
  # Content-Type trust per #509). Size cap handled by AttachmentSizeLimit
  # (above), which honors SPARC_MAX_AVATAR_MB.
  #
  # The controller layer (ProfilesController#update_avatar) is the primary gate
  # — it runs Marcel against the tempfile BEFORE attach. This validator is
  # defense-in-depth for the non-controller paths: API, console, seeds, imports
  # and restores.
  #
  # #892 — this validates the attachable BEING ATTACHED, not the stored blob,
  # and only on saves that actually touch the avatar. The previous form,
  #
  #   validate :avatar_image_type, if: -> { avatar.attached? }
  #
  # was wrong in both halves and the two faults cancelled into a lockout:
  #
  #   * It ran on EVERY save of a user who has an avatar, re-reading the blob
  #     out of the storage service to check something the save was not
  #     changing. A user whose stored avatar did not pass therefore could not
  #     be saved at all — no deactivate!, no disable!, no reactivate!, no
  #     issue_temporary_password!. An administrator could not disable the
  #     account, which is an access-control action failing in the unsafe
  #     direction. #857 fixed the sign-in symptom of this; this is the cause.
  #   * At the moment of upload it did NOT actually validate. Validators run
  #     before save, so the blob was not yet in the service, the
  #     FileNotFoundError rescue fired, and the check was skipped — deferring
  #     it to "the next save", which is exactly what created the first fault.
  #     The path it was written to guard was the one path it never guarded.
  #
  # Sniffing the attachable fixes both: a bad file is rejected at attach time
  # on every path, and an unrelated save never touches storage.
  #
  # The bytes are sniffed directly rather than trusting `blob.content_type`.
  # ActiveStorage derives that via Marcel with the DECLARED type and filename
  # as hints, so a "definitely not an image" body sent as image/png can come
  # back image/png — precisely the client-supplied trust #509 removed.
  ALLOWED_AVATAR_MIME_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  validate :avatar_image_type, if: -> { attachment_changes["avatar"].present? }
  # #878 — belt to deactivate!'s braces. `suspend` writes status directly, and
  # suspended accounts fail `active?` just as deactivated ones do, so the
  # lockout is reachable through more than one door. Validating the transition
  # closes every current path and any future one.
  validate :protect_last_active_admin, if: :will_save_change_to_status?

  def avatar_image_type
    change = attachment_changes["avatar"]
    # A purge (DeleteOne) carries no attachable — nothing to type-check.
    return unless change.respond_to?(:attachable)

    actual = sniff_attachable_mime(change.attachable)
    # Unreadable attachable (a signed id we cannot resolve, a closed io). Say
    # nothing rather than guess: the controller gate still applies, and
    # inventing a failure here would block legitimate uploads.
    return if actual.nil?
    return if ALLOWED_AVATAR_MIME_TYPES.include?(actual)

    errors.add(:avatar, "must be a PNG, JPG, GIF, or WebP image (detected #{actual.inspect})")
  end

  # Read the magic bytes of whatever was handed to `attach`. Duck-typed rather
  # than matched against Rack::Test::UploadedFile and friends, which are not
  # loaded in production.
  def sniff_attachable_mime(attachable)
    case attachable
    when Hash
      io = attachable[:io] || attachable["io"]
      io && sniff_io(io)
    when ActiveStorage::Blob
      attachable.open { |io| Marcel::MimeType.for(io) }
    when String
      ActiveStorage::Blob.find_signed(attachable)&.open { |io| Marcel::MimeType.for(io) }
    else
      if attachable.respond_to?(:tempfile)  # ActionDispatch / Rack::Test uploaded file
        sniff_io(attachable.tempfile)
      elsif attachable.respond_to?(:read)
        sniff_io(attachable)
      end
    end
  rescue Errno::ENOENT, IOError, ActiveStorage::FileNotFoundError,
         ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  # Rewinding afterwards is not optional: ActiveStorage uploads this same io
  # after validation, and a consumed io uploads a truncated file.
  def sniff_io(io)
    io.rewind if io.respond_to?(:rewind)
    Marcel::MimeType.for(io)
  ensure
    io.rewind if io.respond_to?(:rewind)
  end

  # #878 — refuse to move the last active administrator out of `active`.
  #
  # Authentication gates on `active?`, so both "deactivated" and "suspended"
  # are hard lockouts, and reactivation requires another admin — there is no
  # self-service way back. Recovery would mean shell access and a rake task.
  #
  # Reads the PREVIOUS status: an admin already inactive is not the last active
  # admin, and re-saving them must not be blocked.
  def protect_last_active_admin
    return unless admin?
    return unless status_was == "active"
    return if status == "active"
    return if self.class.active.admins.where.not(id: id).exists?

    errors.add(:status,
      "cannot be changed — #{email} is the only active administrator. Promote another " \
      "administrator first, or the instance becomes unadministrable.")
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
  #
  # #878 — the break-glass admin is excluded. Its credential is rotated out of
  # band (sparc-iac and customers rotate the admin and RDS passwords via
  # Lambda), so SPARC auto-deactivating it for idleness would strand the one
  # account that can recover everything else — and `deactivate!` is a hard stop,
  # since SessionsController gates authentication on `active?`.
  #
  # NOT all admins: a named administrator is a person with their own credential
  # and their own recovery path through another admin, so they age out like
  # anyone else. Only the shared bootstrap account is exempt.
  scope :inactive_past_threshold, ->(days) {
    cutoff = days.days.ago
    active
      .where(
        "last_sign_in_at < :cutoff OR (last_sign_in_at IS NULL AND created_at < :cutoff)",
        cutoff: cutoff
      )
      .where.not("LOWER(email) = ?", SparcConfig.admin_email.to_s.downcase.strip)
  }

  # ── Status helpers ──────────────────────────────────────────────────────

  # ── Admin-initiated password reset (#841) ────────────────────────────────
  #
  # Before this, a forgotten local-login password was unrecoverable: an admin
  # could not set one (`user_params` permits only name fields), no self-service
  # flow existed, and the one password screen requires the CURRENT password —
  # which is precisely what has been lost. The only way back in was a Rails
  # console, which on ECS means SSM onto the instance.
  #
  # The admin issues a challenge rather than choosing a password. An admin who
  # types a user's password knows that user's credential, which defeats the
  # point of having per-user authenticators at all (IA-5). So this returns a
  # one-time token the admin conveys out of band; only its SHA-256 digest is
  # stored, exactly as ApiToken does.
  PASSWORD_RESET_WINDOW = ENV.fetch("SPARC_PASSWORD_RESET_MINUTES", "60").to_i.clamp(5, 1440).minutes

  # Returns the PLAINTEXT token. It is never stored and cannot be shown again —
  # issuing a second reset invalidates the first, since the digest is replaced.
  # CodeQL `rb/clear-text-storage-sensitive-data` (alert #21) fires on every
  # write to `must_reset_password` because the attribute NAME contains
  # "password". It is a boolean flag — "does this account owe a password
  # change?" — and carries no credential, so there is nothing to store in clear
  # text.
  #
  # Dismissed in the code-scanning UI, NOT in code. Inline `# codeql[rule-id]`
  # comments were tried here first and did not clear the alert — that
  # suppression mechanism is not honoured for Ruby in this setup. They have
  # been replaced with plain comments, because a directive that looks like it
  # works and does not is worse than a sentence (#846). The rule itself is left
  # enabled repo-wide rather than filtered: it is a good rule, and a future
  # attribute that genuinely does hold a secret should still trip it.
  #
  # The real credential on these paths is handled correctly and is NOT what the
  # alert points at: `password=` runs through has_secure_password, so only the
  # bcrypt digest is persisted, and the reset token is stored as a SHA-256
  # digest with the plaintext returned once and never written down.
  def issue_password_reset!
    plaintext = SecureRandom.urlsafe_base64(48)
    update!(
      password_reset_digest: Digest::SHA256.hexdigest(plaintext),
      password_reset_expires_at: PASSWORD_RESET_WINDOW.from_now,
      must_reset_password: false # boolean flag, not a credential — see above
    )
    plaintext
  end

  # Looked up BY digest so the token itself never has to be compared, and an
  # expired challenge is indistinguishable from a wrong one.
  def self.find_by_password_reset_token(plaintext)
    return nil if plaintext.blank?

    digest = Digest::SHA256.hexdigest(plaintext.to_s)
    where(password_reset_digest: digest)
      .where(password_reset_expires_at: Time.current..)
      .first
  end

  def password_reset_pending? = password_reset_digest.present? && password_reset_expires_at.to_time&.future?

  # ── Flow B: an admin-issued TEMPORARY password, handed over out of band ──
  #
  # The link flow above needs the app to reach the user. Many deployments have
  # no outbound mail at all, and what an administrator actually hands someone in
  # that situation is a password, not a URL.
  #
  # So this sets a real password AND forces a change at first sign-in. The
  # temporary credential is one the admin necessarily knows, which is precisely
  # why it must not survive the first login (IA-5): the user signs in with it
  # and is immediately required to replace it with one only they know.
  #
  # Any outstanding reset link is invalidated — two live paths into one account
  # is one more than anybody intended.
  # #877 — extracted so PROVISIONING can use the same generator. An account's
  # first credential is exactly as admin-known as a reset one, and generating it
  # in two places is how they end up differing in strength.
  def self.generate_temporary_password
    "#{SecureRandom.alphanumeric(16)}-#{SecureRandom.random_number(1000)}"
  end

  def issue_temporary_password!
    temporary = self.class.generate_temporary_password
    update!(
      password: temporary,
      password_confirmation: temporary,
      must_reset_password: true, # boolean flag, not a credential — see above
      password_changed_at: nil,
      password_reset_digest: nil,
      password_reset_expires_at: nil
    )
    temporary
  end

  # #877 — the same handover, applied to an UNSAVED user at provisioning time.
  #
  # Before this, an admin typed a password into the new-user form and the user
  # was never made to replace it: a credential the admin chose, knew, and which
  # survived indefinitely. password_expired? could not catch it either, because
  # it returns false when password_changed_at is blank — exactly the state a
  # freshly provisioned account is in.
  #
  # Returns the plaintext for the caller to hand over once. Never persisted;
  # the database keeps only the bcrypt digest.
  def assign_temporary_password
    temporary = self.class.generate_temporary_password
    self.password              = temporary
    self.password_confirmation = temporary
    self.must_reset_password   = true # boolean flag, not a credential — see above
    self.password_changed_at   = nil
    temporary
  end

  # Single-use: the challenge is cleared in the same transaction that sets the
  # password, so a replayed link cannot set it a second time. `must_reset_password`
  # is cleared too — unlike the temporary-password flow, the user has just chosen
  # this one themselves, so forcing another change immediately would strand them
  # in the very screen they cannot use.
  def redeem_password_reset!(password:, password_confirmation:)
    transaction do
      self.password = password
      self.password_confirmation = password_confirmation
      self.password_reset_digest = nil
      self.password_reset_expires_at = nil
      self.must_reset_password = false # boolean flag, not a credential — see above
      self.password_changed_at = Time.current
      save
    end
  end

  def active?      = status == "active"
  def suspended?   = status == "suspended"
  def deactivated? = status == "deactivated"

  # #878 — raised rather than silently refusing. A caller that thinks it
  # deactivated an account and did not is worse than a visible failure.
  class LastAdminError < StandardError; end

  # True when this is the only active administrator left. Deactivating them
  # locks everyone out of administration, and there is no self-service way
  # back — reactivation requires another admin.
  def last_active_admin?
    return false unless admin?
    return false unless active?

    self.class.active.admins.where.not(id: id).none?
  end

  # Soft-delete: set status to deactivated with timestamp and reason.
  #
  # #878 — the guard lives HERE, not in a controller, because `deactivate!` has
  # four callers: InactivityCheckJob (automatic), Admin::UsersController,
  # Admin::ServiceAccountsController, and organizations. A controller-level
  # check would leave the automatic path open — and that is the one that
  # strands you silently, since nobody is watching when a scheduled job
  # deactivates the last admin for idleness.
  #
  # Authentication gates on `active?`, so this is a hard lockout rather than a
  # forced password change, and there is no recovery short of shell access.
  def deactivate!(reason: "admin_action")
    if last_active_admin?
      raise LastAdminError,
            "#{email} is the only active administrator. Promote another administrator " \
            "before deactivating this account, or the instance becomes unadministrable."
    end

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

  # ── Break-glass account (#878) ───────────────────────────────────────────

  # The shared bootstrap admin named by SPARC_ADMIN_EMAIL.
  #
  # One definition, because three places now ask the question — the FIDO2
  # enrollment gate (authentication.rb), the inactivity scope above, and
  # password expiry below — and three inline copies is how they drift apart.
  #
  # Deliberately keyed on the configured email, NOT on `admin?`. This exempts
  # THE break-glass account, not everyone holding the admin bit. It matches the
  # line the FIDO2 gate already draws: "a shared local account fronted by an
  # external role-checkout/PAM flow".
  #
  # casecmp? on purpose — an email differing only in case must not slip past
  # the exemption and get deactivated, which is the exact outcome it prevents.
  def break_glass_admin?
    email.to_s.casecmp?(SparcConfig.admin_email.to_s)
  end

  # ── Password expiry ──────────────────────────────────────────────────────

  # Returns true when a local-auth user's password is older than the
  # configured expiry threshold. OAuth/SSO-only users are exempt.
  def password_expired?
    return false if break_glass_admin?           # #878 — rotated out of band
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

  # #770 bug 6 — org-admin membership on a specific organization. This is the
  # "appropriate permissions" lever for org-scoped actions (e.g. attaching an
  # unassigned boundary): SPARC has no org-scoped permission catalog, so the
  # `org_admin` OrganizationMembership role is the gate. Instance admins are
  # checked separately by the caller. NIST AC-6 (least privilege).
  def org_admin_of?(organization)
    return false if organization.nil?

    organization_memberships.exists?(organization_id: organization.id, role: "org_admin")
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

  # #857 — update_columns, deliberately not update!.
  #
  # `update!` re-ran EVERY validation on every successful authentication,
  # including `avatar_image_type`, which opens the avatar blob from the storage
  # service. Two consequences:
  #
  #   1. A user whose stored avatar failed validation could not sign in AT ALL.
  #      The login raised RecordInvalid and the request ended in a 422, through
  #      every entry point that calls `start_session` — not just the API session
  #      bridge where it was first seen. Not reachable through the UI today,
  #      because ProfilesController sniffs before attaching, but it made the
  #      avatar rule a lockout switch: tightening the accepted content types or
  #      adding a size cap would instantly lock out every user whose stored
  #      avatar no longer passed, and it would present as "login is broken"
  #      with nothing pointing at an avatar rule. Seeds, imports, restores and
  #      console attaches are the other ways in.
  #   2. Every sign-in paid for a storage read of the avatar, to validate
  #      something the request was not changing.
  #
  # These three columns are internal bookkeeping — no user input, and nothing an
  # unrelated validation has any business gating — so writing them directly is
  # both the smallest fix and the honest one. `updated_at` is set explicitly
  # because update_columns does not touch it, keeping the observable writes
  # identical to the update! this replaces.
  #
  # NIST 800-53: AC-7 / AU-2 (the sign-in record still happens, it just stops
  # being contingent on unrelated validations).
  def record_sign_in!(ip_address: nil)
    now = Time.current
    update_columns(
      last_sign_in_at: now,
      last_sign_in_ip: ip_address,
      sign_in_count: sign_in_count + 1,
      updated_at: now
    )
  end

  # Whether this user can authenticate with a security key (#779).
  def webauthn_registered?
    webauthn_credentials.exists?
  end

  # The stable WebAuthn user handle — the userHandle a discoverable credential
  # returns at usernameless login. Generated lazily on first enrollment and never
  # changed thereafter (rotating it would orphan every registered key).
  def webauthn_handle
    return webauthn_id if webauthn_id.present?

    update!(webauthn_id: WebAuthn.generate_user_id)
    webauthn_id
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
