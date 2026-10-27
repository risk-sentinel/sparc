# frozen_string_literal: true

# #1101 — where one of the ATO wizard's document steps (SSP, SAP, SAR, POA&M)
# starts. The wizard used to start every step on Skip, re-asking for what the
# boundary already had.
#
#   exactly one of the boundary's own  → "select_existing", that one chosen,
#                                         labelled as the boundary's current one
#   several of the boundary's own      → "select_existing", none chosen: they are
#                                         listed and the author picks
#   none                               → "skip"
#
# "Choose another" and "Create new" stay available either way. Only documents
# already on this boundary count as its own; a boundary-less one an
# administrator may attach is still offered, never chosen for them.
class AtoWizardStep
  SELECT = "select_existing"
  SKIP = "skip"

  attr_reader :mode, :current, :own

  def self.for(boundary, candidates)
    own = candidates.select { _1.authorization_boundary_id == boundary.id }
    case own.size
    when 0 then new(mode: SKIP, current: nil, own: own)
    when 1 then new(mode: SELECT, current: own.first, own: own)
    else new(mode: SELECT, current: nil, own: own)
    end
  end

  def initialize(mode:, current:, own:)
    @mode = mode
    @current = current
    @own = own
  end

  def several? = own.size > 1

  def selected_id = current&.id

  def mode?(name) = mode == name.to_s
end
