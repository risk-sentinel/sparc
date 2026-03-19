class CreateProjectOrchestration < ActiveRecord::Migration[8.1]
  def change
    # ── Projects ──────────────────────────────────────────────────
    create_table :projects do |t|
      t.string  :name,        null: false
      t.text    :description
      t.string  :status,      null: false, default: "draft"
      t.text    :authorization_boundary_description
      t.timestamps
    end

    add_index :projects, :status

    # ── Boundaries ────────────────────────────────────────────────
    create_table :boundaries do |t|
      t.references :project,    null: false, foreign_key: { on_delete: :cascade }
      t.string     :name,       null: false
      t.text       :description
      t.string     :environment, null: false, default: "production"
      t.timestamps
    end

    # ── Boundary ↔ CdefDocument join table ────────────────────────
    create_table :boundary_cdef_documents do |t|
      t.references :boundary,      null: false, foreign_key: { on_delete: :cascade }
      t.references :cdef_document,  null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end

    add_index :boundary_cdef_documents, [ :boundary_id, :cdef_document_id ],
              unique: true, name: "idx_boundary_cdef_unique"

    # ── Project Memberships ───────────────────────────────────────
    create_table :project_memberships do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.string     :user_name,  null: false
      t.string     :user_email
      t.string     :role,       null: false
      t.timestamps
    end

    add_index :project_memberships, [ :project_id, :role ]

    # ── Link existing artifact tables to projects ─────────────────
    add_reference :ssp_documents,  :project, foreign_key: { on_delete: :nullify }
    add_reference :sap_documents,  :project, foreign_key: { on_delete: :nullify }
    add_reference :sar_documents,  :project, foreign_key: { on_delete: :nullify }
    add_reference :poam_documents, :project, foreign_key: { on_delete: :nullify }
  end
end
