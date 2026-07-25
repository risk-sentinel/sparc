# frozen_string_literal: true

# #447 — one HDF ingest event, scoped to an AuthorizationBoundary. Holds summary
# counts and the sha256 of the uploaded bundle; the per-control detail lives in
# scanner_findings. Translation state, not a system of record — a tenant may
# re-ingest a fresh scan at any time.
class ScanRun < ApplicationRecord
  belongs_to :authorization_boundary
  has_many :scanner_findings, dependent: :destroy

  before_validation :assign_uuid_if_blank
  before_validation :default_ingested_at, on: :create

  validates :scanner, presence: true
  validates :ingested_at, presence: true
  validates :uuid, presence: true

  scope :recent, -> { order(ingested_at: :desc) }

  def to_param
    uuid
  end

  private

  def assign_uuid_if_blank
    self.uuid = SecureRandom.uuid if uuid.blank?
  end

  def default_ingested_at
    self.ingested_at ||= Time.current
  end
end
