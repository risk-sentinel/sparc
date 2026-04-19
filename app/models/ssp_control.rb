class SspControl < ApplicationRecord
  belongs_to :ssp_document
  belongs_to :parent, class_name: "SspControl", optional: true
  has_many :provider_statements, class_name: "SspControl", foreign_key: :parent_id,
           dependent: :destroy, inverse_of: :parent
  has_many :ssp_control_fields, dependent: :destroy
  has_many :ssp_control_statements, dependent: :delete_all
  has_many :ssp_by_components, dependent: :delete_all
  has_many :control_back_matter_links, as: :linkable, dependent: :destroy
  has_many :back_matter_resources, through: :control_back_matter_links

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

  # Statement helpers (#393).

  def statements_count
    ssp_control_statements.size
  end

  def parent_statements
    ssp_control_statements.where(parent_statement_id: nil).order(:row_order)
  end

  def child_statements_for(parent_id)
    ssp_control_statements.where(parent_statement_id: parent_id).order(:row_order)
  end

  # Joined implementation prose across all statements -- mirrors the SAP
  # `aggregate_objective_text` pattern. Used by exporters as a fallback
  # when no per-statement records exist.
  def aggregate_implementation_text
    return nil if ssp_control_statements.empty?
    ssp_control_statements.order(:row_order).map do |s|
      label = s.label.presence || s.statement_id
      "[#{label}] #{s.implementation_prose}".strip
    end.reject(&:blank?).join("\n\n").presence
  end
end
