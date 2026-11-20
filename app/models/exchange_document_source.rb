# frozen_string_literal: true

# One document SPARC pulls from a connection (#1354): its address, its format
# and document type, and how often to pull it. Only documents set here are
# pulled; crawling the trust center only lists candidates (owner, 2026-11-20).
#
# NIST SP 800-53: CA-3, SA-9, CA-7 (scheduled collection).
class ExchangeDocumentSource < ApplicationRecord
  FORMATS = DocumentValidationService::FORMATS

  belongs_to :exchange_connection, inverse_of: :document_sources
  has_many :received_documents, dependent: :nullify

  validates :format, inclusion: { in: FORMATS }
  validates :pull_interval_hours, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 24 * 31 }
  validates :url, uniqueness: { scope: :exchange_connection_id }
  validate :url_is_https

  scope :enabled, -> { where(enabled: true) }

  # Due when never pulled, or when its interval has passed.
  def due?(now = Time.current)
    enabled? && (last_pulled_at.nil? || last_pulled_at <= now - pull_interval_hours.hours)
  end

  # The stream a pulled version belongs to: one per document address.
  def stream_key = "pull:source:#{id}"

  private

  def url_is_https
    uri = URI(url.to_s)
    errors.add(:url, "must be an https:// address") unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    errors.add(:url, "is not a valid address")
  end
end
