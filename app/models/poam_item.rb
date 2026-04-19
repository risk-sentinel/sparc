class PoamItem < ApplicationRecord
  belongs_to :poam_document
  # #393: optional link to the SSP implementation statement this POA&M item
  # is remediating. Set on item edit form (statement picker) or on import
  # when the item description references a known statement.
  belongs_to :ssp_control_statement, optional: true

  has_many :poam_item_risks, dependent: :delete_all
  has_many :poam_risks, through: :poam_item_risks
  has_many :poam_item_observations, dependent: :delete_all
  has_many :poam_observations, through: :poam_item_observations
  has_many :poam_item_findings, dependent: :delete_all
  has_many :poam_findings, through: :poam_item_findings

  def primary_risk
    poam_risks.order("poam_item_risks.id").first
  end

  # NIST 800-53 control ID pattern: 2-3 letters, dash, 1-3 digits, optional
  # enhancement like .1 or (1). Matches "ac-2", "AC-02", "sc-8.1", "AC-2(3)".
  CONTROL_ID_REGEX = /\b([A-Z]{2,3})-(\d{1,3})(?:\.(\d+)|\((\d+)\))?\b/i

  # Scan free-text fields and props for NIST 800-53 control references.
  # POAM items don't have a structural related-controls field in OSCAL — the
  # convention is to mention the control in the description/remarks
  # (e.g. "Mapped to NIST 800-53 control sc-8") or in a props entry. Returns
  # uniq, lowercased control IDs (e.g. ["sc-8", "ac-2.1"]).
  def related_control_ids
    sources = [ description, remarks ]
    Array(props_data).each do |prop|
      next unless prop.is_a?(Hash)
      name = prop["name"].to_s.downcase
      sources << prop["value"] if name.include?("control") || name == "implementation-statement"
    end
    sources.compact.flat_map { |text| text.to_s.scan(CONTROL_ID_REGEX) }
           .map { |fam, num, enh1, enh2|
             base = "#{fam.downcase}-#{num.to_i}"
             enh = enh1 || enh2
             enh ? "#{base}.#{enh}" : base
           }
           .uniq
  end

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
      internal_notes: internal_notes,
      closure_evidence: closure_evidence,
      risk_count: poam_risks.size,
      observation_count: poam_observations.size,
      finding_count: poam_findings.size
    }
  end
end
