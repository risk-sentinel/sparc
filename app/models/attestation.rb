class Attestation < ApplicationRecord
  belongs_to :evidence

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

  ROLE_LABELS = {
    "control_owner" => "Control Owner",
    "system_owner" => "System Owner",
    "isso" => "ISSO",
    "ciso" => "CISO",
    "assessor" => "Assessor",
    "authorizing_official" => "Authorizing Official"
  }.freeze

  def role_label
    ROLE_LABELS[role] || role&.titleize || "Unknown"
  end

  def generate_signature!
    payload = "#{attester_name}|#{attester_email}|#{statement}|#{attested_at.iso8601}|#{evidence_id}"
    self.signature_hash = Digest::SHA256.hexdigest(payload)
    save!
  end
end
