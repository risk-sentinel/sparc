# Polymorphic inheritance link from an SSP control statement to its
# source — either a CdefControlStatement (#398 CDEF → SSP prose
# auto-population) or a CatalogControlPart/SspControlStatement on a
# leveraged SSP (#396 leveraged authorizations). `overridden` marks
# statements the user has edited locally so bulk resync leaves them alone.
#
# NIST OSCAL: corresponds to `link[rel="implements"]` (CDEF source) and
# `link[rel="inherited"]` (leveraged SSP source) on the leveraging
# statement. `source_uuid` round-trips through export/import so links
# survive OSCAL JSON serialization.
class SspControlStatementInheritance < ApplicationRecord
  belongs_to :ssp_control_statement
  belongs_to :source, polymorphic: true

  SOURCE_TYPES = %w[CdefControlStatement SspControlStatement].freeze

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :source_uuid, presence: true,
                          format: { with: BackMatterResource::UUID_V4_REGEX }
  validates :ssp_control_statement_id,
            uniqueness: { scope: [ :source_type, :source_id ] }

  scope :from_cdef,      -> { where(source_type: "CdefControlStatement") }
  scope :from_leveraged, -> { where(source_type: "SspControlStatement") }
  scope :active,         -> { where(overridden: false) }

  # Returns the prose currently in effect: the user's local edit if
  # overridden, otherwise the live source prose.
  def effective_prose
    overridden? ? overridden_prose : source.implementation_prose
  end

  # Mark as overridden and snapshot the edit. Called from the update
  # controller when the user edits a previously-inherited statement.
  def override!(new_prose)
    update!(overridden: true, overridden_prose: new_prose)
  end

  # Drop the override and resync to the current source prose.
  def reset_to_source!
    transaction do
      update!(overridden: false, overridden_prose: nil)
      ssp_control_statement.update!(implementation_prose: source.implementation_prose)
    end
  end
end
