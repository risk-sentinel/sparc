class ControlCatalog < ApplicationRecord
  include OscalMetadata
  include SafeDestroyable
  include Sluggable

  has_many :control_families, dependent: :destroy
  has_many :catalog_controls, through: :control_families
  has_many :profile_documents
  has_many :source_mappings, class_name: "ControlMapping", foreign_key: :source_catalog_id
  has_many :target_mappings, class_name: "ControlMapping", foreign_key: :target_catalog_id

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  def total_controls
    catalog_controls.count
  end

  def oscal_document_version
    version
  end

  private

  def deletion_dependencies
    deps = []
    deps << "#{profile_documents.count} profile(s)" if profile_documents.exists?
    deps << "source for #{source_mappings.count} mapping(s)" if source_mappings.exists?
    deps << "target for #{target_mappings.count} mapping(s)" if target_mappings.exists?
    deps
  end
end
