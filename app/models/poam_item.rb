class PoamItem < ApplicationRecord
  belongs_to :poam_document
  has_many :poam_item_fields, dependent: :delete_all

  def to_hash
    {
      title: title,
      description: description,
      poam_item_uuid: poam_item_uuid,
      risk_status: risk_status,
      risk_level: risk_level,
      likelihood: likelihood,
      impact: impact,
      deadline: deadline,
      row_order: row_order,
      fields: poam_item_fields.map do |field|
        {
          field_name: field.field_name,
          field_value: field.field_value,
          editable: field.editable
        }
      end
    }
  end
end
