# Adds global-vs-boundary scope columns to cdef_documents.
#
# CDEFs are unique among the 6 OSCAL document types: SSP/SAP/SAR/POAM
# are each owned by exactly one AuthorizationBoundary. CDEFs can be
# either (a) attached to specific Boundary records via the existing
# boundary_cdef_documents join (boundary-scoped) or (b) globally
# available within an organization so any boundary's SSP can compose
# them in.
#
# Mirrors the precedent on back_matter_resources (globally_available
# boolean + organization_id + partial index where true) introduced in
# #371.
class AddGlobalScopeToCdefDocuments < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:cdef_documents, :globally_available)
      add_column :cdef_documents, :globally_available, :boolean,
                 default: false, null: false
    end

    unless column_exists?(:cdef_documents, :organization_id)
      add_reference :cdef_documents, :organization,
                    null: true, foreign_key: { on_delete: :nullify }, index: true
    end

    # Partial index -- only index global rows since they're the ones
    # SSP authoring scans across all orgs/boundaries. Mirrors
    # idx_back_matter_resources_global pattern.
    unless index_exists?(:cdef_documents, :globally_available, name: "idx_cdef_documents_global")
      add_index :cdef_documents, :globally_available,
                where: "globally_available = true",
                name:  "idx_cdef_documents_global"
    end
  end

  def down
    if index_exists?(:cdef_documents, :globally_available, name: "idx_cdef_documents_global")
      remove_index :cdef_documents, name: "idx_cdef_documents_global"
    end
    if column_exists?(:cdef_documents, :organization_id)
      remove_reference :cdef_documents, :organization, foreign_key: true
    end
    if column_exists?(:cdef_documents, :globally_available)
      remove_column :cdef_documents, :globally_available
    end
  end
end
