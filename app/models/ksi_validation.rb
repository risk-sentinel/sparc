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
end
