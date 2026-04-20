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

  # #396 + #398: inheritance links from a CDEF statement (auto-populated
  # implementation prose) or from an upstream SSP (leveraged authorization).
  has_many :inheritance_links,
           class_name: "SspControlStatementInheritance",
           foreign_key: :ssp_control_statement_id,
           dependent: :destroy

  validates :uuid, presence: true,
                   format: { with: BackMatterResource::UUID_V4_REGEX }
  validates :statement_id, presence: true,
                           uniqueness: { scope: :ssp_control_id }

  # Attributes the controller is allowed to update via the edit modal.
  EDITABLE_ATTRIBUTES = %i[implementation_prose remarks
                           responsible_roles_data set_parameters_data].freeze

  # Classify where this statement's prose came from. Drives the UI badges
  # on `_statements_table.html.erb` and determines whether the "Reset to
  # source" action is available.
  #
  # :authored           — no inheritance link; user wrote this themselves
  # :cdef               — populated from a CDEF component
  # :leveraged          — inherited via a leveraged authorization
  # :overridden_cdef    — started as CDEF but the user has edited
  # :overridden_leveraged — started as leveraged but the user has edited
  def source_kind
    link = inheritance_links.first
    return :authored unless link
    base = link.source_type == "CdefControlStatement" ? :cdef : :leveraged
    link.overridden? ? :"overridden_#{base}" : base
  end

  def inherited?
    inheritance_links.exists?
  end
end
