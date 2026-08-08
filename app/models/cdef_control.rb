class CdefControl < ApplicationRecord
  # #911 — deliberately NOT canonicalised, unlike the other control-bearing
  # models. This column is mixed-vocabulary: an AWS Labs CDEF stores Security
  # Hub ids (`IAM.3`), a STIG stores NIST resolved through CCI, and a plain
  # InSpec profile stores its own control names. `ControlId.canonical` encodes
  # NIST numbering and case, so applying it here mutated `IAM.3` into `iam.3`
  # and broke the SecHub enrichment lookups outright.
  #
  # The fix is structural, not a normalisation tweak: the source identifier
  # belongs in its own column, preserved exactly as it arrived, with the NIST
  # control it maps to enriched alongside it — which is what the AWS importer
  # already does via the `nist_oscal_ids` field. Canonicalisation becomes safe
  # here once `control_id` is guaranteed to hold the NIST reference — tracked as
  # #912. Until then CDEF form-matching goes through `ControlId.forms`.

  belongs_to :cdef_document
  has_many :cdef_control_fields, dependent: :delete_all
  has_many :cdef_control_statements, dependent: :delete_all
  has_many :control_back_matter_links, as: :linkable, dependent: :destroy
  has_many :back_matter_resources, through: :control_back_matter_links

  before_save :compute_control_family

  # #911 — a STIG rule reaches NIST through CCI (rule → CCI → 800-53). Where
  # that resolution fails there is no control to name, so `control_id` is NULL
  # and the XCCDF identity survives in `stig_id`. That pair is the unmapped
  # state: it must be shown to a human with a remedy, never left silently blank.
  scope :unmapped_stig_rules, -> {
    where(control_id: [ nil, "" ]).where.not(stig_id: [ nil, "" ])
  }

  # Statement helpers (#393). Same shape as SspControl#statements_count etc.
  def statements_count
    cdef_control_statements.size
  end

  def parent_statements
    cdef_control_statements.where(parent_statement_id: nil).order(:row_order)
  end

  def aggregate_implementation_text
    return nil if cdef_control_statements.empty?
    cdef_control_statements.order(:row_order).map do |s|
      label = s.label.presence || s.statement_id
      "[#{label}] #{s.implementation_prose}".strip
    end.reject(&:blank?).join("\n\n").presence
  end

  # This rule carries STIG provenance but resolved to no catalog control (#911).
  def unmapped_stig_rule?
    control_id.blank? && stig_id.present?
  end

  # The identifier to show when there is no control to name.
  def provenance_id
    stig_id.presence || rule_id.presence || group_id.presence
  end

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

    # #911 — a blank control_id is now a normal state (an unmapped STIG rule
    # has no control to name), and `"".split("-").first` is nil, so the
    # unguarded `.upcase` here raised NoMethodError on save. It was masked
    # before only because the parsers always wrote *something* into the column
    # and the bulk-insert path skips this callback entirely.
    #
    # The same idiom is unguarded in seven other places (SapControl,
    # ProfileControl and five controller sites) — tracked as #913, which folds
    # all of them into one helper rather than leaving nine copies.
    self.control_family = control_id.to_s.split("-").first&.upcase.presence
  end
end
