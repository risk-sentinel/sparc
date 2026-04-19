# Per-statement implementation response on an SSP control.
#
# OSCAL maps to control-implementation.implemented-requirements[].statements[].
# Each row is keyed to a catalog statement_id (e.g. "ac-1_smt.a") and
# carries the SSP author's response in `implementation_prose`.
#
# READ-ONLY fields (set at backfill or import; controller never permits):
#   - statement_id  : OSCAL id from the catalog (immutable reference)
#   - label         : human label from the catalog
#   - parent_statement_id : nesting from the catalog
#
# EDITABLE fields (`update_statement` controller action permits these):
#   - implementation_prose, remarks, responsible_roles_data, set_parameters_data
#
# UUID stability invariant (#397): the `uuid` is OscalUuidService.derived(
#   ssp_control.uuid, "ssp-statement", statement_id) for backfilled rows so
#   exports stay byte-identical across re-runs.
class SspControlStatement < ApplicationRecord
  belongs_to :ssp_control
  has_many :sar_findings, dependent: :nullify
  has_many :poam_items, dependent: :nullify

  validates :uuid, presence: true,
                   format: { with: BackMatterResource::UUID_V4_REGEX }
  validates :statement_id, presence: true,
                           uniqueness: { scope: :ssp_control_id }

  # Attributes the controller is allowed to update via the edit modal.
  EDITABLE_ATTRIBUTES = %i[implementation_prose remarks
                           responsible_roles_data set_parameters_data].freeze
end
