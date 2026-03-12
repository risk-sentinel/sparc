class ControlCatalog < ApplicationRecord
  include OscalMetadata

  # Prevent deletion when any profile or mapping still references this catalog.
  # Must be declared before associations with dependent: options so it runs first.
  before_destroy :ensure_no_linked_documents

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

  def ensure_no_linked_documents
    dependents = []
    dependents << "#{profile_documents.count} profile(s)" if profile_documents.exists?
    dependents << "source for #{source_mappings.count} mapping(s)" if source_mappings.exists?
    dependents << "target for #{target_mappings.count} mapping(s)" if target_mappings.exists?

    if dependents.any?
      errors.add(:base, "Cannot delete catalog: linked to #{dependents.join(', ')}")
      throw(:abort)
    end
  end
end
