# NIST SA-10: Developer Configuration Management
# Tracks seed section completion status and versions for idempotent,
# resilient seeding with passive catch-up on deployment.
class SeedSection < ApplicationRecord
  STATUSES = %w[pending completed failed skipped].freeze

  validates :name, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :pending, -> { where(status: "pending") }

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end
end
