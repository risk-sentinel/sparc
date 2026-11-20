# frozen_string_literal: true

# One version of a document a boundary received (#1354): pulled from a
# connection or uploaded by a person. Never overwritten: its bytes, SHA-256,
# format and where it came from are fixed when it is stored; only the review
# fields change afterwards.
#
# Each STREAM (a pulled document address, or a boundary's uploads of one
# document type) has at most one accepted version in effect. Owner,
# 2026-11-20: a document of any format belongs to the boundary only once the
# receiving boundary accepts it. A version that fails validation is stored
# with its errors, shown, and can never be accepted.
#
# States:
#   pending_review — waiting for a reviewer
#   accepted       — in effect for its stream
#   responded      — the reviewer asked the provider for information; still
#                    not in effect
#   rejected       — on record, never in effect
#   superseded     — was accepted; a later version replaced it
#   invalid        — failed validation; on record with its errors
#
# NIST SP 800-53: CA-3, SI-10, SI-7 and AU-10 (bytes and SHA-256 fixed at
# receipt), AU-12, CA-7.
class ReceivedDocument < ApplicationRecord
  STATES = %w[pending_review accepted responded rejected superseded invalid].freeze
  SOURCES = %w[pull upload push].freeze
  REVIEW_ACTIONS = %w[accept respond reject auto_accept].freeze
  OPEN_STATES = %w[pending_review responded].freeze

  belongs_to :authorization_boundary
  belongs_to :exchange_connection, optional: true
  belongs_to :exchange_document_source, optional: true
  belongs_to :received_by, class_name: "User", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  belongs_to :scan_run, optional: true
  has_one_attached :file

  attr_readonly :authorization_boundary_id, :source, :stream_key, :format, :document_type,
                :sha256, :byte_size, :received_at, :received_by_id

  validates :source, inclusion: { in: SOURCES }
  validates :state, inclusion: { in: STATES }
  validates :format, inclusion: { in: DocumentValidationService::FORMATS }
  validates :sha256, format: { with: /\A\h{64}\z/ }
  validates :stream_key, presence: true
  validates :review_action, inclusion: { in: REVIEW_ACTIONS }, allow_nil: true

  scope :recent, -> { order(received_at: :desc, id: :desc) }
  scope :in_effect, -> { where(state: "accepted") }
  scope :awaiting_review, -> { where(state: OPEN_STATES) }

  def open? = OPEN_STATES.include?(state)
  def in_effect? = state == "accepted"

  # The version now in effect for this one's stream, if any.
  def in_effect_version
    self.class.in_effect.where(stream_key: stream_key).where.not(id: id).order(:received_at).last
  end

  def validation_errors = Array(validation["errors"])
  def validation_warnings = Array(validation["warnings"])
  def delta_changes = Array(delta["changes"])

  def bytes = file.attached? ? file.download : nil
end
