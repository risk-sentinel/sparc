class SarControl < ApplicationRecord
  belongs_to :sar_document
  has_many :sar_control_fields, dependent: :delete_all
  has_many :control_back_matter_links, as: :linkable, dependent: :destroy
  has_many :back_matter_resources, through: :control_back_matter_links

  # Multiple test rows can share the same Paragraph (control_id)
  # and a row may have no Paragraph — no uniqueness or presence enforced
  validates :control_id, presence: false

  scope :in_section, ->(s) { where(section: s) }
  scope :boundary_findings, -> { where(subject_asset: nil) }

  accepts_nested_attributes_for :sar_control_fields

  before_save :compute_control_family

  def to_hash
    {
      control_id: control_id,
      title: title,
      section: section,
      subject_asset: subject_asset,
      subject_environment: subject_environment,
      row_order: row_order,
      fields: sar_control_fields.map do |field|
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
    self.control_family = control_id.to_s.split("-").first&.upcase.presence
  end
end
