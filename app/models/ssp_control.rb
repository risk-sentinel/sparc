class SspControl < ApplicationRecord
  belongs_to :ssp_document
  has_many :ssp_control_fields, dependent: :destroy
  
  validates :control_id, presence: true, uniqueness: { scope: :ssp_document_id }
  
  accepts_nested_attributes_for :ssp_control_fields
  
  def to_hash
    {
      control_id: control_id,
      title: title,
      fields: ssp_control_fields.map do |field|
        {
          field_name: field.field_name,
          field_value: field.field_value,
          editable: field.editable
        }
      end
    }
  end
end