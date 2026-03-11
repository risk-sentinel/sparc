class ControlCatalog < ApplicationRecord
  include OscalMetadata

  has_many :control_families, dependent: :destroy
  has_many :catalog_controls, through: :control_families

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true, uniqueness: true

  def total_controls
    catalog_controls.count
  end

  def oscal_document_version
    version
  end
end
