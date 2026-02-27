class TprControl < ApplicationRecord
  belongs_to :tpr_document
  has_many :tpr_control_fields, dependent: :destroy
  
  validates :control_id, presence: true, uniqueness: { scope: :tpr_document_id }
  
  accepts_nested_attributes_for :tpr_control_fields
  
  def to_hash
    {
      control_id: control_id,
      title: title,
      fields: tpr_control_fields.map do |field|
        {
          field_name: field.field_name,
          field_value: field.field_value,
          editable: field.editable
        }
      end
    }
  end
end