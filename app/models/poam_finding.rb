class PoamFinding < ApplicationRecord
  belongs_to :poam_document

  has_many :poam_item_findings, dependent: :delete_all
  has_many :poam_items, through: :poam_item_findings
  has_many :poam_finding_observations, dependent: :delete_all
  has_many :poam_observations, through: :poam_finding_observations
  has_many :poam_finding_risks, dependent: :delete_all
  has_many :poam_risks, through: :poam_finding_risks

  # #840 — reject a finding that cannot form valid OSCAL, at the point of entry.
  #
  # `uuid` used to be the only validation, and HdfAggregationService wrote
  # findings with no `target`. OSCAL requires uuid/title/description/target on a
  # finding, so ONE aggregation run made the entire POA&M fail schema validation
  # in every serialization — and the failure surfaced at export, with the user
  # bounced back to `?oscal_validation_failed=1` and nothing saying which record
  # was at fault.
  #
  # `target` is what was assessed and the resulting state; it is the substance
  # of a finding, not decoration. Same reasoning and same shape as the #832
  # rules on PoamRisk: enforced on every save (grandfathering would preserve the
  # invalid data this exists to stop), never defaulted, and pre-existing rows
  # found with `bin/rails sparc:poam:audit_findings` rather than one failed edit
  # at a time.
  OSCAL_REQUIRED_FIELDS = %i[title description target_data].freeze

  validates :uuid, presence: true
  validates(*OSCAL_REQUIRED_FIELDS, presence: true)

  def missing_required_fields
    OSCAL_REQUIRED_FIELDS.select { |field| public_send(field).blank? }
  end
end
