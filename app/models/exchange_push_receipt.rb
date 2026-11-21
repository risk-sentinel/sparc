# frozen_string_literal: true

# One push a provider made to a connection (#1354): a signed notice that a
# registered document changed, carrying the document's bytes.
#
# The push never decides what is stored. SPARC pulls the document fresh from
# its registered address (ExchangePushConfirmJob):
#
#   confirmed    the pulled bytes hash to what was pushed; the pulled version
#                is the one received
#   unconfirmed  they do not, or the address could not be reached; the pushed
#                bytes are received as an unconfirmed push, flagged, and wait
#                for a reviewer like any other changed version
#   pending      the pull has not run yet
#
# The signature's SHA-256 is unique, so a captured request cannot be
# replayed. The pushed bytes are held on the receipt only until the pull
# decides; afterwards they live on the received document, if anywhere.
#
# NIST SP 800-53: CA-3, SC-23 and AU-10 (signed, replay-proof), AU-12, SI-7.
class ExchangePushReceipt < ApplicationRecord
  STATUSES = %w[pending confirmed unconfirmed].freeze

  belongs_to :exchange_connection, inverse_of: :push_receipts
  belongs_to :exchange_document_source, optional: true
  belongs_to :received_document, optional: true
  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }
  validates :sha256, format: { with: /\A\h{64}\z/ }
  validates :signature_sha256, presence: true, uniqueness: true
  validates :key_fingerprint, :signed_at, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def pending? = status == "pending"
  def confirmed? = status == "confirmed"
  def unconfirmed? = status == "unconfirmed"

  def bytes = file.attached? ? file.download : nil
end
