class CdefControl < ApplicationRecord
  belongs_to :cdef_document
  has_many :cdef_control_fields, dependent: :delete_all
  has_many :control_back_matter_links, as: :linkable, dependent: :destroy
  has_many :back_matter_resources, through: :control_back_matter_links

  before_save :compute_control_family

  def to_hash
    h = {
      control_id: control_id,
      title: title,
      severity: severity,
      group_id: group_id,
      rule_id: rule_id,
      cci_references: cci_references,
      control_family: control_family,
      row_order: row_order,
      fields: cdef_control_fields.map do |field|
        {
          field_name: field.field_name,
          field_value: field.field_value,
          editable: field.editable
        }
      end
    }
    h[:stig_id] = stig_id if stig_id.present?
    h
  end

  private

  def compute_control_family
    return if control_family.present?
    self.control_family = control_id.to_s.split("-").first.upcase.presence
  end
end
