class ProfileControl < ApplicationRecord
  belongs_to :profile_document
  has_many :profile_control_fields, dependent: :delete_all

  validates :control_id, presence: true,
                         uniqueness: { scope: :profile_document_id, message: "already exists in this profile" }

  before_save :compute_control_family

  def to_hash
    {
      control_id: control_id,
      title: title,
      priority: priority,
      control_family: control_family,
      row_order: row_order,
      fields: profile_control_fields.map do |field|
        {
          field_name: field.field_name,
          field_value: field.field_value,
          editable: field.editable
        }
      end
    }
  end

  private

  def compute_control_family
    return if control_family.present?
    self.control_family = control_id.to_s.split("-").first.upcase.presence
  end
end
