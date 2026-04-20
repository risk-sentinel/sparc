class CreateLeveragedAuthAndInheritanceTables < ActiveRecord::Migration[8.1]
  def change
    # Polymorphic inheritance: links a leveraging SSP statement to its
    # source — either a CdefControlStatement (#398) or an SspControlStatement
    # on a leveraged SSP (#396). `overridden` marks local edits so refresh
    # jobs don't clobber them.
    create_table :ssp_control_statement_inheritances do |t|
      t.references :ssp_control_statement, null: false, foreign_key: { on_delete: :cascade }, index: { name: "idx_inh_on_target_stmt" }
      t.string  :source_type, null: false
      t.bigint  :source_id,   null: false
      t.string  :source_uuid, null: false
      t.boolean :overridden,  null: false, default: false
      t.text    :overridden_prose
      t.timestamps
    end
    add_index :ssp_control_statement_inheritances, [ :source_type, :source_id ],
              name: "idx_inh_on_source"
    add_index :ssp_control_statement_inheritances, :source_uuid,
              name: "idx_inh_on_source_uuid"
    add_index :ssp_control_statement_inheritances,
              [ :ssp_control_statement_id, :source_type, :source_id ],
              unique: true, name: "idx_inh_unique_target_source"

    # Boundary-to-boundary leveraged authorization (#396). The leveraged
    # boundary may be null when the leveraging org doesn't have access to
    # the leveraged system in SPARC (Scenarios 2 + 3 — CRM upload).
    create_table :leveraged_authorizations do |t|
      t.string :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :leveraging_boundary, null: false,
                   foreign_key: { to_table: :authorization_boundaries, on_delete: :cascade }
      t.references :leveraged_boundary, null: true,
                   foreign_key: { to_table: :authorization_boundaries, on_delete: :nullify }
      t.string :name, null: false
      t.string :crm_type, null: false, default: "oscal_with_access"
      t.date   :date_authorized
      t.text   :description
      t.jsonb  :metadata, default: {}
      t.timestamps
    end
    add_index :leveraged_authorizations, :uuid, unique: true
    add_index :leveraged_authorizations,
              [ :leveraging_boundary_id, :leveraged_boundary_id ],
              name: "idx_la_unique_pair"

    # Components on the leveraged side that the leveraging system inherits.
    # Per NIST slide 20: each LA gets its own component representing the
    # leveraged system + components for shared capabilities.
    create_table :leveraged_authorization_components do |t|
      t.references :leveraged_authorization, null: false, foreign_key: { on_delete: :cascade }
      t.string :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :title, null: false
      t.string :component_type, null: false, default: "this-system"
      t.text   :description
      t.jsonb  :props_data, default: []
      t.timestamps
    end
    add_index :leveraged_authorization_components, :uuid, unique: true

    # CRM/SSRM as a back-matter resource on the leveraging boundary
    # (Scenarios 2 + 3). The `crm_type` column lets views filter to the
    # CRM uploads separately from ordinary back-matter.
    add_column :back_matter_resources, :crm_type, :string
    add_index  :back_matter_resources, :crm_type
  end
end
