class ControlCatalog < ApplicationRecord
  include OscalMetadata

  has_many :control_families, dependent: :destroy
  has_many :catalog_controls, through: :control_families

  validates :name, presence: true, uniqueness: true

  def total_controls
    catalog_controls.count
  end

  # OscalMetadata expects a version method matching the pattern *_version
  alias_method :catalog_version, :version

  def oscal_document_version
    version
  end
end
