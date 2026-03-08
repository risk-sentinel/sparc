class EvidenceControlLink < ApplicationRecord
  belongs_to :evidence

  validates :control_id, presence: true
  validates :control_id, uniqueness: { scope: [ :evidence_id, :document_type, :document_id ] }

  DOCUMENT_TYPES = %w[SspDocument SarDocument SapDocument CdefDocument PoamDocument].freeze

  def document
    return nil unless document_type.present? && document_id.present?
    document_type.constantize.find_by(id: document_id)
  end
end
