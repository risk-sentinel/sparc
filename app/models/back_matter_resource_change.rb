# Append-only audit row capturing a single field change or workflow event
# on a BackMatterResource. Used for promotion audit trail, federation
# provenance, and version history.
#
# NIST AU-2: Audit Events — every promotion, approval, rejection, archive,
#            restore, and federation import generates one or more rows here.
# NIST AU-3: Content of Audit Records — captures who, when, what changed.
class BackMatterResourceChange < ApplicationRecord
  CHANGE_TYPES = %w[
    create
    update
    promote
    approve
    reject
    archive
    restore
    federate
    supersede
  ].freeze

  belongs_to :back_matter_resource, inverse_of: :changes_log
  belongs_to :changed_by_user, class_name: "User", optional: true

  validates :change_type, presence: true, inclusion: { in: CHANGE_TYPES }
  validates :changed_at, presence: true

  scope :chronological,        -> { order(:changed_at, :id) }
  scope :reverse_chronological, -> { order(changed_at: :desc, id: :desc) }
  scope :for_batch, ->(batch_uuid) { where(batch_uuid: batch_uuid) }
end
