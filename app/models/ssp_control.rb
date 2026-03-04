class SspControl < ApplicationRecord
  belongs_to :ssp_document
  belongs_to :parent, class_name: "SspControl", optional: true
  has_many :provider_statements, class_name: "SspControl", foreign_key: :parent_id,
           dependent: :destroy, inverse_of: :parent
  has_many :ssp_control_fields, dependent: :destroy

  # Paragraph/ReqID is null for provider statement rows — allow it
  validates :control_id, uniqueness: { scope: :ssp_document_id, allow_nil: true }

  default_scope { order(:row_order) }

  scope :roots, -> { where(parent_id: nil) }
  scope :provider_statements_only, -> { where.not(parent_id: nil) }

  accepts_nested_attributes_for :ssp_control_fields

  def provider_statement?
    parent_id.present?
  end

  def to_hash
    {
      control_id: control_id,
      title: title,
      row_order: row_order,
      fields: ssp_control_fields.map do |field|
        {
          field_name: field.field_name,
          field_value: field.field_value,
          editable: field.editable
        }
      end,
      provider_statements: provider_statements.map(&:to_hash)
    }
  end
end
