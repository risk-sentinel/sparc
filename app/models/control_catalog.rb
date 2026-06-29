class ControlCatalog < ApplicationRecord
  include OscalMetadata
  include Searchable
  include SafeDestroyable
  include Sluggable
  include Lifecycle
  include Approvable

  has_many :control_families, dependent: :destroy
  has_many :catalog_controls, through: :control_families
  has_many :profile_documents
  has_many :source_mappings, class_name: "ControlMapping", foreign_key: :source_catalog_id
  has_many :target_mappings, class_name: "ControlMapping", foreign_key: :target_catalog_id

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  before_validation :ensure_oscal_uuid

  validates :name, presence: true

  def total_controls
    catalog_controls.count
  end

  def oscal_document_version
    version
  end

  # First 8 characters of the SHA-256 content digest for display.
  def short_digest
    catalog_content_digest&.slice(0, 8)
  end

  private

  def ensure_oscal_uuid
    self.oscal_uuid ||= SecureRandom.uuid
  end

  def deletion_dependencies
    deps = []
    deps << "#{profile_documents.count} profile(s)" if profile_documents.exists?
    deps << "source for #{source_mappings.count} mapping(s)" if source_mappings.exists?
    deps << "target for #{target_mappings.count} mapping(s)" if target_mappings.exists?
    deps
  end
end
