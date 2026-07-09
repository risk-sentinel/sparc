class Attestation < ApplicationRecord
  belongs_to :evidence

  # #680 — an attestation change (added, re-reviewed on a new date, status flip,
  # or removed) is a material change to the artifact, so it mints a new evidence
  # artifact version even when the file is unchanged.
  after_commit :reversion_artifact, on: [ :create, :update, :destroy ]

  validates :attester_name, presence: true
  validates :statement, presence: true
  validates :attested_at, presence: true

  ROLES = %w[
    control_owner system_owner isso ciso assessor authorizing_official
  ].freeze

  # Defense-in-depth: even though `role` is attestation metadata (not an
  # app-level authorization role), we restrict it to the controlled vocabulary
  # so mass-assignment cannot set arbitrary values. Pairs with the brakeman
  # BRAKE0105 ignore entry — the field name 'role' looks dangerous to the
  # static analyzer but is bounded by this inclusion check.
  validates :role, inclusion: { in: ROLES }, allow_nil: true

  # Periodic-review cadence; aligns with CMS / SAF CLI attestation schema (#440).
  FREQUENCIES = %w[daily weekly monthly quarterly annually ad_hoc].freeze
  validates :frequency, inclusion: { in: FREQUENCIES }, allow_nil: true

  # CMS attestation `status` field. SPARC's existing attestations were
  # implicitly affirmative; default of "passed" preserves that semantic.
  STATUSES = %w[passed failed].freeze
  validates :status, inclusion: { in: STATUSES }

  ROLE_LABELS = {
    "control_owner" => "Control Owner",
    "system_owner" => "System Owner",
    "isso" => "ISSO",
    "ciso" => "CISO",
    "assessor" => "Assessor",
    "authorizing_official" => "Authorizing Official"
  }.freeze

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

  def role_label
    ROLE_LABELS[role] || role&.titleize || "Unknown"
  end

  def frequency_label
    FREQUENCY_LABELS[frequency] || frequency&.titleize
  end

  def generate_signature!
    payload = "#{attester_name}|#{attester_email}|#{statement}|#{attested_at.iso8601}|#{evidence_id}"
    self.signature_hash = Digest::SHA256.hexdigest(payload)
    save!
  end

  private

  def reversion_artifact
    evidence&.record_artifact_version_if_changed(reason: "attestation")
  end
end
