class EvidenceControlLink < ApplicationRecord
  belongs_to :evidence

  validates :control_id, presence: true
  validates :control_id, uniqueness: { scope: [ :evidence_id, :document_type, :document_id ] }

  DOCUMENT_TYPES = %w[SspDocument SarDocument SapDocument CdefDocument PoamDocument].freeze

  after_create :sync_back_matter_resource
  after_destroy :cleanup_back_matter_resource

  def document
    return nil unless document_type.present? && document_id.present?
    document_type.constantize.find_by(id: document_id)
  end

  private

  # Ensure a BackMatterResource exists for this evidence on the linked document
  def sync_back_matter_resource
    doc = document
    return unless doc && evidence&.uuid.present?

    BackMatterResource.find_or_create_by!(
      resourceable: doc,
      evidence: evidence,
      uuid: evidence.uuid
    ) do |r|
      r.title = evidence.title || "Evidence: #{evidence.evidence_type}"
      r.description = "#{evidence.evidence_type&.titleize} evidence linked to #{control_id}"
      r.media_type = evidence.file&.content_type if evidence.file&.attached?
      # Durable resolver href (#680) instead of a bare filename, so the stored
      # back-matter reference resolves across rename/re-upload/URL rotation.
      r.href = evidence.oscal_resolver_url
      r.source = "managed"
    end
  end

  # Remove back-matter resource if no more links exist for this evidence on this document
  def cleanup_back_matter_resource
    doc = document
    return unless doc && evidence

    remaining = EvidenceControlLink.where(
      evidence: evidence,
      document_type: document_type,
      document_id: document_id
    ).where.not(id: id).exists?

    unless remaining
      BackMatterResource.where(resourceable: doc, evidence: evidence).destroy_all
    end
  end
end
