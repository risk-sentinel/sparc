class SarRisk < ApplicationRecord
  include RiskRating

  belongs_to :sar_result

  has_many :sar_risk_observations, dependent: :delete_all
  has_many :sar_observations, through: :sar_risk_observations
  has_many :sar_finding_risks, dependent: :delete_all
  has_many :sar_findings, through: :sar_finding_risks

  STATUSES = %w[open investigating remediating deviation-requested deviation-approved closed].freeze

  # #1090 — OSCAL requires uuid/title/description/statement/status on a risk in
  # assessment-results, exactly as it does in a POA&M. `uuid` was the only
  # validation here, so a SAR risk could be created with none of the content the
  # exporter emits, and the gap only surfaced at export.
  #
  # DELIBERATELY NOT `deadline`. PoamRisk requires one because a POA&M without a
  # time commitment is not a plan (#832) — that is a SPARC rule about POA&Ms, not
  # an OSCAL rule, and it does not apply to an assessment result.
  #
  # Safe to enforce on existing rows: measured on the seeded estate, 0 of 17
  # sar_risks were missing any of the four.
  OSCAL_REQUIRED_FIELDS = %i[title description statement status].freeze

  validates :uuid, presence: true
  validates(*OSCAL_REQUIRED_FIELDS, presence: true)

  # The fields this risk still needs, so a client can highlight them rather than
  # parse "validation failed" prose.
  def missing_required_fields
    OSCAL_REQUIRED_FIELDS.select { |field| public_send(field).blank? }
  end
end
