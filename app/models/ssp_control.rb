class SspControl < ApplicationRecord
  include ControlIdentifiable
  include ControlOrdering
  canonicalises_control_id :control_id

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
      # #1028 — the stable identity a field import can address unambiguously.
      uuid: uuid,
      control_id: control_id,
      title: title,
      row_order: row_order,
      # #1312 — the retired control-level fields (status, origination, …) are
      # each item's own now and are left out; `editable` is read from the
      # current vocabulary, not the flag a row was saved with, so the editor
      # never offers a field the save would refuse.
      fields: ssp_control_fields.reject { SspControlField::RETIRED_FIELDS.include?(_1.field_name) }.map do |field|
        {
          field_name: field.field_name,
          field_value: field.field_value,
          editable: SspControlField::EDITABLE_FIELDS.include?(field.field_name)
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

  # The control's answers, item by item, labelled: "[a.] … [b.] …". #1312 —
  # read by SAP generation and the HDF export. An unanswered item contributes
  # nothing: it used to contribute its bare label, so a control with no answers
  # read "[ac-2_smt]" instead of nil.
  def aggregate_implementation_text
    ssp_control_statements.sort_by { _1.row_order || 0 }.filter_map do |s|
      next if s.implementation_prose.blank?

      "[#{s.label.presence || s.statement_id}] #{s.implementation_prose.strip}"
    end.join("\n\n").presence
  end
end
