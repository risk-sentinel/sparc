# Per-statement implementation response on a CDEF control.
#
# OSCAL maps to component-definition.components[].control-implementations[]
# .implemented-requirements[].statements[]. Each row is keyed to a catalog
# statement_id and carries the component vendor's response in
# `implementation_prose`.
#
# READ-ONLY fields (set at backfill or import):
#   - statement_id, label, parent_statement_id (catalog references)
#
# EDITABLE fields (allowed by `update_statement` controller action):
#   - implementation_prose, remarks, set_parameters_data
#
# UUID stability invariant (#397): backfilled UUIDs are
#   OscalUuidService.derived(cdef_control.uuid, "cdef-statement", statement_id)
class CdefControlStatement < ApplicationRecord
  belongs_to :cdef_control

  validates :uuid, presence: true,
                   format: { with: BackMatterResource::UUID_V4_REGEX }
  validates :statement_id, presence: true,
                           uniqueness: { scope: :cdef_control_id }

  EDITABLE_ATTRIBUTES = %i[implementation_prose remarks set_parameters_data].freeze
end
