# Read-only first-class catalog parts (OSCAL controls[].parts[]).
#
# Authored by the catalog publisher (NIST). The `prose` field is the
# policy language itself (e.g. "Develop, document, and disseminate an
# access control policy..."). Downstream consumers (SSP/CDEF/SAR/POAM)
# reference parts by `part_id` -- they do not edit the catalog text.
#
# This model has NO controller. Catalog admin edits go through the
# existing catalog-level CRUD flows; per-part editing is out of scope
# for #393.
#
# part_name distinguishes the kind of part. NIST 800-53 typically emits:
#   - "statement"           : the requirement language (used by SSP/CDEF)
#   - "guidance"            : supplemental implementation guidance
#   - "assessment-objective": determination statements (used by SAP/SAR
#                             objectives -- see #390)
#   - "assessment-method"   : how-to-assess parts
class CatalogControlPart < ApplicationRecord
  belongs_to :catalog_control

  validates :uuid, presence: true,
                   format: { with: BackMatterResource::UUID_V4_REGEX }
  validates :part_id, presence: true,
                      uniqueness: { scope: :catalog_control_id }
  validates :part_name, presence: true

  scope :statements,            -> { where(part_name: "statement") }
  scope :assessment_objectives, -> { where(part_name: "assessment-objective") }
  scope :guidance,              -> { where(part_name: "guidance") }
end
