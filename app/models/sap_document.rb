class SapDocument < ApplicationRecord
  include OscalMetadata

  has_many :sap_controls, dependent: :delete_all
  has_one_attached :file

  belongs_to :ssp_document, optional: true
  belongs_to :profile_document, optional: true

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  ASSESSMENT_TYPES = %w[initial annual continuous ad-hoc].freeze
  ASSESSMENT_METHODS = %w[examine interview test].freeze

  def to_json_data
    {
      document_name: name,
      sap_version: sap_version,
      description: description,
      assessment_type: assessment_type,
      assessment_start: assessment_start,
      assessment_end: assessment_end,
      assessors: assessors,
      assessment_scope: assessment_scope,
      ssp_document_name: ssp_document&.name,
      profile_document_name: profile_document&.name,
      controls: sap_controls.order(:row_order).includes(:sap_control_fields).map(&:to_hash)
    }
  end

  def method_counts
    sap_controls.group(:assessment_method).count
  end

  def status_counts
    sap_controls.group(:assessment_status).count
  end
end
