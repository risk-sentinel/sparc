class SapControl < ApplicationRecord
  belongs_to :sap_document
  has_many :sap_control_fields, dependent: :delete_all
  has_many :control_back_matter_links, as: :linkable, dependent: :destroy
  has_many :back_matter_resources, through: :control_back_matter_links

  validates :control_id, presence: true

  before_save :compute_control_family

  ASSESSMENT_METHODS = %w[examine interview test].freeze
  ASSESSMENT_STATUSES = %w[planned in-progress completed].freeze

  # Returns assessment methods as an array. Stored comma-separated in
  # the assessment_method column (e.g. "examine,interview" for controls
  # that require multiple assessment methods).
  def assessment_methods
    return [] if assessment_method.blank?
    assessment_method.to_s.split(",").map { |m| m.strip.downcase }.reject(&:blank?).uniq
  end

  def multiple_methods?
    assessment_methods.size > 1
  end

  def to_hash
    {
      control_id: control_id,
      title: title,
      control_family: control_family,
      assessment_method: assessment_method,
      assessment_status: assessment_status,
      assessor_name: assessor_name,
      objective: objective,
      test_case: test_case,
      row_order: row_order,
      fields: sap_control_fields.map do |field|
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
