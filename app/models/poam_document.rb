class PoamDocument < ApplicationRecord
  include OscalMetadata

  belongs_to :project, optional: true

  has_many :poam_items, dependent: :delete_all
  has_many :poam_risks, dependent: :delete_all
  has_many :poam_observations, dependent: :delete_all
  has_many :poam_findings, dependent: :delete_all
  has_many :poam_local_components, dependent: :delete_all
  has_one_attached :file

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  RISK_STATUSES = %w[open investigating remediating deviation-requested deviation-approved closed].freeze

  def to_json_data
    {
      document_name: name,
      poam_version: poam_version,
      oscal_version: oscal_version,
      system_id: system_id,
      risks_count: poam_risks.count,
      observations_count: poam_observations.count,
      findings_count: poam_findings.count,
      items: poam_items.order(:row_order).map(&:to_hash)
    }
  end
end
