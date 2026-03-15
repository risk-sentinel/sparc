class SarDocument < ApplicationRecord
  include OscalMetadata
  include SafeDestroyable
  include Sluggable

  belongs_to :authorization_boundary, optional: true

  has_many :sar_controls, dependent: :delete_all
  has_many :sar_results, dependent: :delete_all
  has_many :sar_local_components, dependent: :delete_all
  has_one_attached :file

  belongs_to :sap_document, optional: true

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true
  validates :file_type, inclusion: { in: %w[excel json xml yaml] }, allow_nil: true
  validates :creation_method, inclusion: { in: %w[excel wizard oscal_import] }, allow_nil: true

  CREATION_METHODS = %w[excel wizard oscal_import].freeze

  def wizard_created?
    creation_method == "wizard"
  end

  def oscal_imported?
    creation_method == "oscal_import"
  end

  def enriched?
    description.present? ||
      sar_results.exists? ||
      sar_local_components.exists? ||
      import_ap_href.present?
  end

  def to_json_data
    {
      document_name: name,
      controls: sar_controls.order(:row_order).includes(:sar_control_fields).map(&:to_hash)
    }
  end
end
