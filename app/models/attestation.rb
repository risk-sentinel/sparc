# An attestation is evidence whose substance is WHO asserted something, so its
# provenance controls matter more than most.
#
# NIST 800-53 Controls:
#   AC-3  Access Enforcement — the claimed role is verified against what the
#         attester actually holds on the evidence's authorization boundary,
#         through `evidence.attest` rather than `evidence.write` (#947).
#   AC-5  Separation of Duties — `assessor_3pao` is deliberately NOT granted
#         `evidence.attest`: an assessor must not vouch for the evidence it will
#         later assess independently.
#   AC-6  Least Privilege — the authority to assert is a distinct permission
#         key, not an implication of being able to upload a file.
#   AU-10 Non-Repudiation — the attester is bound to an account, and
#         `attester_name` is a snapshot taken at signing time that no later
#         rename or role change rewrites (#934 rule).
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Attestation < ApplicationRecord
  belongs_to :evidence

  # #947 / #934 — who asserted this, as a reference rather than a name.
  #
  # Optional at the column level because rows written before this existed cannot
  # be resolved automatically: an `attester_name` string is not reliably a
  # person. Those rows stay readable; the validation below is what requires a
  # resolved attester on the next write, so history is preserved and new claims
  # are checked. See `db/migrate/*_add_attester_user_to_attestations.rb`.
  belongs_to :attester_user, class_name: "User", optional: true

  # #680 — an attestation change (added, re-reviewed on a new date, status flip,
  # or removed) is a material change to the artifact, so it mints a new evidence
  # artifact version even when the file is unchanged.
  after_commit :reversion_artifact, on: [ :create, :update, :destroy ]

  # #934 — the display name is a SNAPSHOT taken when the attester is set, never
  # derived on read. A later rename, role change or deactivation must not
  # rewrite what the record said at the moment it was signed.
  before_validation :snapshot_attester_name, if: :attester_user_id_changed?

  # #947 — a blank cadence means "not specified", which is `nil`.
  #
  # The form's frequency select offers "Not specified" as `include_blank`, so it
  # posts an EMPTY STRING — and `inclusion: { in: FREQUENCIES }, allow_nil: true`
  # rejects "" because "" is not nil. The result was a save refused with
  # "Frequency is not included in the list" for a field the user deliberately
  # left alone. Normalising here fixes both the nested block and the standalone
  # attestation screen, which posts the same control and carried the same latent
  # defect.
  before_validation { self.frequency = nil if frequency.blank? }

  validates :attester_name, presence: true
  validates :statement, presence: true
  validates :attested_at, presence: true

  # #947 — the authority to assert, distinct from `evidence.write`. Which roles
  # hold it is instance configuration (seeded to the seven accountable boundary
  # roles), so organizations with different rule sets express their own.
  ATTEST_PERMISSION = "evidence.attest"

  # Periodic-review cadence; aligns with CMS / SAF CLI attestation schema (#440).
  FREQUENCIES = %w[daily weekly monthly quarterly annually ad_hoc].freeze
  validates :frequency, inclusion: { in: FREQUENCIES }, allow_nil: true

  # CMS attestation `status` field. SPARC's existing attestations were
  # implicitly affirmative; default of "passed" preserves that semantic.
  STATUSES = %w[passed failed].freeze
  validates :status, inclusion: { in: STATUSES }

  # #947 — the check the issue is about. `evidence.write` is the permission to
  # ADD an attestation; it is not the authority to MAKE the assertion, and for a
  # record whose whole substance is who asserted it, that difference is the
  # point.
  validate :attester_holds_the_attested_role

  FREQUENCY_LABELS = {
    "daily" => "Daily",
    "weekly" => "Weekly",
    "monthly" => "Monthly",
    "quarterly" => "Quarterly",
    "annually" => "Annually",
    "ad_hoc" => "Ad-hoc"
  }.freeze

  # Review cadence → ActiveSupport::Duration, feeding the artifact-freshness
  # "next review due / overdue" deltas (#685). `ad_hoc` has no interval (nil):
  # there is no fixed cadence to compute a due date from.
  FREQUENCY_INTERVALS = {
    "daily"     => 1.day,
    "weekly"    => 1.week,
    "monthly"   => 1.month,
    "quarterly" => 3.months,
    "annually"  => 1.year
  }.freeze

  # The interval for a cadence keyword, or nil (ad_hoc / unknown).
  def self.interval_for(frequency) = FREQUENCY_INTERVALS[frequency]

  # ── Who may attest ────────────────────────────────────────────────────────
  #
  # #947 replaced a hardcoded six-item `ROLES` list with this. That list came in
  # with the original evidence feature and was never reconciled with either role
  # system: five of its six values matched the roster only loosely, and
  # `control_owner` existed in NEITHER the canonical `Role` catalog nor the
  # membership vocabulary — so an attestation could name a role that nobody in
  # the product could actually hold, and no check could ever pass. Deriving the
  # list from the permission removes the possibility of that drift, because
  # there is now one vocabulary rather than two.
  #
  # Every role carrying the permission, at either scope.
  def self.roles_with_attest_permission
    Role.where("permissions @> ?", { ATTEST_PERMISSION => true }.to_json).sorted
  end

  # The roles that may attest against a given boundary.
  #
  # ── Evidence that belongs to a system (boundary present) ──────────────────
  #
  # BOUNDARY-SCOPED ROLES ONLY. `User#has_permission?` matches
  # `authorization_boundary_id: [id, nil]`, so an instance-scoped grant would
  # otherwise satisfy the check on every boundary at once — estate-wide
  # authority to sign for every system. An assertion about a specific system
  # belongs to someone accountable for that system, so an instance grant must
  # not reach here. (The seed strips this permission from the one instance role
  # that would have inherited it by `.dup`; this scope is what stops the rule
  # depending on the seed staying correct.)
  #
  # ── Instance-wide evidence (nil boundary) ─────────────────────────────────
  #
  # Boundary-less evidence is PROVIDER material — it arrives from a leveraged
  # SSP as inherited or common controls — so it belongs to no single system and
  # no System Owner can speak for it. Two legs therefore apply:
  #
  #   * instance-scoped attesting roles (Policy), whose remit is exactly the
  #     estate-wide artefacts no boundary owns; and
  #   * boundary-scoped attesting roles held on ANY boundary (CISO and the rest)
  #     — someone who may sign for at least one system may sign for shared
  #     evidence.
  #
  # The asymmetry is deliberate: Policy reaches global evidence, but does not
  # thereby gain authority over any individual boundary's.
  def self.attestable_roles(authorization_boundary_id: nil)
    return roles_with_attest_permission if authorization_boundary_id.blank?

    roles_with_attest_permission.authorization_boundary_scoped
  end

  # The roles this user may attest under here — the intersection of "carries the
  # permission at a scope that reaches this evidence" and "they actually hold
  # it".
  def self.attestable_roles_for(user:, authorization_boundary_id:)
    return Role.none if user.nil?

    permitted = attestable_roles(authorization_boundary_id: authorization_boundary_id)

    # An Instance Admin may attest without a roster grant — the same bypass
    # `authorize_permission!` carries everywhere, and the same one
    # `attester_holds_the_attested_role` applies on save.
    #
    # This branch is what stops the FORM from contradicting the MODEL. Without
    # it the picker offered an admin as an attester and then found no role they
    # held, so it disabled the role select and an admin could not record an
    # attestation through the UI at all — while the server would have accepted
    # it. A UI-only constraint blocking something the model permits is precisely
    # the defect #947 was filed about; reintroducing one here would be its own
    # small joke.
    return permitted if user.admin?

    held = user.user_roles
    if authorization_boundary_id.present?
      held = held.where(authorization_boundary_id: authorization_boundary_id)
    end

    permitted.where(id: held.select(:role_id))
  end

  # Users who may attest here, for the attester picker.
  #
  # Instance Admins are always included. `admin?` short-circuits
  # `has_permission?` everywhere else in the app, and an admin who appeared in
  # no picker while being able to do everything else would be an inconsistency
  # a user has to discover the hard way.
  def self.eligible_attesters_for(authorization_boundary_id:)
    held = UserRole.where(role_id: attestable_roles(authorization_boundary_id: authorization_boundary_id).select(:id))
    if authorization_boundary_id.present?
      held = held.where(authorization_boundary_id: authorization_boundary_id)
    end

    User.where(id: held.select(:user_id)).or(User.where(admin: true)).order(:email)
  end

  def frequency_label
    FREQUENCY_LABELS[frequency] || frequency&.titleize
  end

  # Human label for the recorded role.
  #
  # Resolves against the `Role` catalog, then falls back to titleizing the
  # stored value. The fallback is what keeps a legacy row readable: an
  # attestation recorded as `control_owner` still renders "Control Owner" even
  # though no such role exists any more. Reporting history is not the same as
  # accepting a new claim, and only the latter is validated.
  def role_label
    return "Unknown" if role.blank?

    Role.find_by(name: role, scope: "authorization_boundary")&.display_name || role.titleize
  end

  # #947 — whether this row satisfies the rule as it stands today. Rows that
  # predate it answer false and are REPORTED rather than rewritten; the
  # validation is what stops a new or re-saved claim from joining them.
  def attester_verified?
    return true unless SparcConfig.any_auth_enabled?
    return false if attester_user.blank? || role.blank?

    boundary_id = evidence&.authorization_boundary_id

    # An Instance Admin may assert, the same way `admin?` short-circuits every
    # other permission check in the app. They still name a real attesting role,
    # so the recorded claim stays inside the closed vocabulary and reads the
    # same as anyone else's.
    if attester_user.admin?
      return self.class.attestable_roles(authorization_boundary_id: boundary_id).exists?(name: role)
    end

    self.class.attestable_roles_for(
      user: attester_user, authorization_boundary_id: boundary_id
    ).exists?(name: role)
  end

  def generate_signature!
    payload = "#{attester_name}|#{attester_email}|#{statement}|#{attested_at.iso8601}|#{evidence_id}"
    self.signature_hash = Digest::SHA256.hexdigest(payload)
    save!
  end

  private

  # Snapshot, not a derivation — see #934. Only fires when the attester changes,
  # so correcting a typo in the statement never rewrites the recorded name.
  def snapshot_attester_name
    return if attester_user.blank?

    self.attester_name  = attester_user.display_label
    self.attester_email = attester_user.email if attester_email.blank?
  end

  # The roster check. Mirrors the no-auth behaviour of every other guard in the
  # app (`BoundaryScopedDocument`, `authorize_permission!`): with no auth method
  # enabled there are no roles to check against, and a single-operator instance
  # must not be locked out of its own evidence.
  def attester_holds_the_attested_role
    return unless SparcConfig.any_auth_enabled?

    if attester_user.blank?
      errors.add(:attester_user, "must be a SPARC account — an attestation has to name someone checkable")
      return
    end

    if role.blank?
      errors.add(:role, "must say which role the attestation is made under")
      return
    end

    boundary_id = evidence&.authorization_boundary_id

    # Instance Admin bypass — consistent with `authorize_permission!`, which
    # admins clear everywhere. The role still has to be a real attesting one, so
    # an admin cannot invent a title; they can only assert under an authority
    # the instance actually recognises.
    if attester_user.admin?
      return if self.class.attestable_roles(authorization_boundary_id: boundary_id).exists?(name: role)

      errors.add(:role, "'#{role_label}' is not a role that may attest. " \
                        "Grant '#{ATTEST_PERMISSION}' to it in Admin > Roles, or choose another.")
      return
    end

    permitted = self.class.attestable_roles_for(user: attester_user, authorization_boundary_id: boundary_id)

    return if permitted.exists?(name: role)

    errors.add(:role, attester_role_error(boundary_id, permitted))
  end

  # Name the missing thing rather than saying "invalid". The three failures are
  # genuinely different problems with genuinely different fixes, and a user who
  # cannot tell them apart cannot act.
  def attester_role_error(boundary_id, permitted)
    where = boundary_id.present? ? "on #{evidence.authorization_boundary&.name || 'this boundary'}" : "on any boundary"

    unless self.class.attestable_roles(authorization_boundary_id: boundary_id).exists?(name: role)
      return "'#{role_label}' is not a role that may attest. " \
             "Grant '#{ATTEST_PERMISSION}' to it in Admin > Roles, or choose another."
    end

    if permitted.none?
      return "#{attester_name} holds no role #{where} that may attest. " \
             "Add them to the boundary roster with an attesting role first."
    end

    "#{attester_name} does not hold '#{role_label}' #{where}. " \
    "They may attest as: #{permitted.map(&:display_name).sort.join(', ')}."
  end

  def reversion_artifact
    evidence&.record_artifact_version_if_changed(reason: "attestation")
  end
end
