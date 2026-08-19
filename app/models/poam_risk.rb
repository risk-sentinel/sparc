class PoamRisk < ApplicationRecord
  belongs_to :poam_document

  has_many :poam_remediations, dependent: :delete_all
  has_many :poam_milestones, through: :poam_remediations

  has_many :poam_item_risks, dependent: :delete_all
  has_many :poam_items, through: :poam_item_risks
  has_many :poam_risk_observations, dependent: :delete_all
  has_many :poam_observations, through: :poam_risk_observations
  has_many :poam_finding_risks, dependent: :delete_all
  has_many :poam_findings, through: :poam_finding_risks

  STATUSES = %w[open investigating remediating deviation-requested deviation-approved closed].freeze

  # #832 — reject a risk that cannot form a valid, actionable POA&M, at the
  # point of entry rather than at export.
  #
  # `uuid` used to be the only validation, so a risk could be saved with no
  # title, description, statement, status or deadline. Two consequences:
  #
  #   1. It let invalid OSCAL be CREATED and only fail much later at export,
  #      far from the input that caused it and with no indication of which
  #      record was at fault. OSCAL requires uuid/title/description/statement/
  #      status on a risk. This is the #816 bug class at its source: #816 fixed
  #      the seed data so the demo POA&M exported cleanly, but nothing stopped
  #      the next incomplete risk arriving through the API, the UI or an import.
  #
  #   2. A risk with no deadline is not a plan. `deadline` is a SPARC rule
  #      rather than an OSCAL one — OSCAL does not require it — but a POA&M
  #      whose items carry no time commitment is not a POA&M an assessor or AO
  #      would accept, and `hdf convert --from oscal-poam` correctly REFUSES an
  #      item whose risks carry no usable deadline.
  #      (hdf-cli 3.3.2 used to invent "conversion time + one year"; 3.4.1
  #      stopped, which is the behaviour we want. Re-verified on 3.5.1: same
  #      refusal, same message the API matches on.)
  #
  #      The command takes `--from oscal-poam` with no `--to` — the default
  #      output is HDF. `oscal-poam → hdf-amendments` is not a conversion
  #      hdf-cli offers; POA&M flows the other way, from an amendments doc
  #      (mitre/hdf-libs#104, and MITRE's own use-case docs).
  #
  # Enforced on every save, not just create. Grandfathering existing rows would
  # keep exactly the invalid data this exists to stop, and silently. Rows that
  # predate the rule are found with `bin/rails sparc:poam:audit_risks` and
  # completed by a human — none of these fields can be synthesised without
  # inventing compliance content.
  OSCAL_REQUIRED_FIELDS = %i[title description statement status].freeze

  validates :uuid, presence: true
  validates(*OSCAL_REQUIRED_FIELDS, presence: true)
  validates :deadline, presence: true

  # The fields a given risk is missing, for the audit task and for error
  # reporting on import — where naming the record and the gap is the difference
  # between an actionable message and "validation failed".
  def missing_required_fields
    (OSCAL_REQUIRED_FIELDS + [ :deadline ]).select { |field| public_send(field).blank? }
  end
end
