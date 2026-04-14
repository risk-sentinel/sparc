class ProfileControl < ApplicationRecord
  belongs_to :profile_document
  has_many :profile_control_fields, dependent: :delete_all
  has_many :control_back_matter_links, as: :linkable, dependent: :destroy
  has_many :back_matter_resources, through: :control_back_matter_links

  validates :control_id, presence: true,
                         uniqueness: { scope: :profile_document_id, message: "already exists in this profile" }

  before_save :compute_control_family

  # Returns the control ID in human-readable format for display.
  # Converts OSCAL canonical format to label-style:
  #   "ac-2.1" → "AC-2(1)"   "ac-1" → "AC-1"
  def display_id
    control_id.to_s.upcase.gsub(/\.(\d+)/) { "(#{$1})" }
  end

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
