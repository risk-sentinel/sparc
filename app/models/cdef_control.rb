class CdefControl < ApplicationRecord
  # #912 — canonicalisation is safe here again, because `control_id` now holds
  # ONLY a NIST reference.
  #
  # #911 had to disable it: the column was mixed-vocabulary (AWS Security Hub
  # `IAM.3`, STIG rules, InSpec control names, NIST), and `ControlId.canonical`
  # encodes NIST numbering and case, so it rewrote `IAM.3` to `iam.3` and broke
  # the Security Hub enrichment lookups outright. The fix was structural rather
  # than a normalisation tweak: the source identifier moved to its own column,
  # preserved exactly as it arrived, with the NIST control it maps to resolved
  # alongside it — the pattern the AWS importer had already proved by writing
  # `nist_oscal_ids` next to an untouched `control_id`.
  #
  # `source_control_id` is NEVER canonicalised. That is the point of it.
  include ControlIdentifiable
  include ControlOrdering
  canonicalises_control_id :control_id

  # Framework the source identifier came from. Recorded at import rather than
  # inferred from the shape of the string later — sniffing `IAM.3` versus `ac-2`
  # is precisely the guesswork this column exists to end.
  SOURCE_VOCABULARIES = %w[nist disa_stig aws_security_hub cis scap_oval fedramp_ksi].freeze

  validates :source_vocabulary, inclusion: { in: SOURCE_VOCABULARIES }, allow_nil: true

  # The identifier as it arrived, whatever the framework. Falls back to the
  # legacy columns so rows read correctly between the schema migration and the
  # deferred backfill completing.
  def source_identifier
    source_control_id.presence || stig_id.presence || rule_id.presence || group_id.presence
  end

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
  # #912 — one accessor, so callers stop reaching into the STIG-specific
  # columns. Kept as an alias because the display paths already call it.
  def provenance_id
    source_identifier
  end

  def to_hash
    h = {
      # #1028 — the addressable identity. `control_id` is the NIST reference a
      # Converter resolved at ingest (#912): non-unique by design and NULL where
      # nothing resolved, so it cannot be what a caller addresses by. `uuid` is
      # exact; `source_control_id` + `source_vocabulary` are the identifier the
      # caller actually holds (an AWS Security Hub id, a CCI, a CIS id).
      uuid: uuid,
      control_id: control_id,
      source_control_id: source_control_id,
      source_vocabulary: source_vocabulary,
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
