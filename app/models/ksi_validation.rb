# NIST: CA-2 (Assessment), CA-7 (Continuous Monitoring), PM-6 (Measures of Performance)
# FedRAMP 20x KSI validation tracking — records assessment status and evidence
# for each Key Security Indicator within an authorization boundary.
class KsiValidation < ApplicationRecord
  belongs_to :authorization_boundary
  belongs_to :catalog_control
  belongs_to :evidence, optional: true

  STATUSES = %w[not_assessed passed failed partial expired].freeze
  METHODS  = %w[automated manual hybrid].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :validation_method, inclusion: { in: METHODS }, allow_nil: true
  validates :catalog_control_id, uniqueness: { scope: :authorization_boundary_id,
    message: "already has a validation for this KSI in this boundary" }
  validate :evidence_within_boundary

  before_validation :generate_uuid, on: :create
  before_save :check_expiration

  scope :overdue, -> { where("next_validation_due < ?", Time.current) }
  scope :due_soon, ->(days = 7) { where("next_validation_due BETWEEN ? AND ?", Time.current, days.days.from_now) }
  scope :by_status, ->(s) { where(status: s) }
  scope :by_theme, ->(code) {
    joins(catalog_control: :control_family).where(control_families: { code: code })
  }

  delegate :control_family, to: :catalog_control

  def theme_code
    control_family.code
  end

  def theme_name
    control_family.name
  end

  def ksi_id
    catalog_control.control_id
  end

  def ksi_title
    catalog_control.title
  end

  def expired?
    next_validation_due.present? && next_validation_due < Time.current
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def check_expiration
    if next_validation_due.present? && next_validation_due < Time.current && status == "passed"
      self.status = "expired"
    end
  end

  # #851 — evidence_id is mass-assignable through the API, and nothing else
  # checked that the referenced Evidence belongs to the boundary in the URL. A
  # caller scoped to boundary A could attach boundary B's evidence and read it
  # back: the detailed serializer returns the evidence title, type, status and
  # file_hash inline, so this disclosed tenant data rather than merely dangling
  # a foreign key.
  #
  # Enforced as a model validation rather than by scoping the lookup in the
  # controller, because a controller-level `@boundary.evidences.find` guards
  # only the paths someone remembers to change — this covers every writer,
  # including the console and future callers.
  #
  # Fails closed on a nil boundary: evidence whose boundary was nullified is not
  # attachable to a scoped validation, which is the safe reading of an
  # ambiguous record rather than a special case worth permitting.
  #
  # NIST 800-53: AC-3 (Access Enforcement), AC-4 (Information Flow
  # Enforcement), SC-4 (Information in Shared Resources).
  # Compares the association OBJECTS rather than the foreign keys. On an
  # unsaved record both ids are nil, so an id comparison reads "equal" and
  # waves through exactly the record it exists to reject. ActiveRecord's `==`
  # falls back to object identity when the id is nil, which gives the right
  # answer for saved and unsaved records alike.
  def evidence_within_boundary
    return if evidence.nil?

    own_boundary = authorization_boundary
    return if own_boundary.present? && evidence.authorization_boundary == own_boundary

    errors.add(:evidence, "must belong to the same authorization boundary")
  end
end
