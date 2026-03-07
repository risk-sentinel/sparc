class OscalFullSchemaUplift < ActiveRecord::Migration[8.1]
  def change
    # ── Catalog tables ──────────────────────────────────────────────
    change_table :control_catalogs do |t|
      t.string :uuid
      t.string :oscal_version
      t.jsonb  :metadata_extra,   default: {}, null: false
      t.jsonb  :back_matter_data, default: [], null: false
    end

    change_table :control_families do |t|
      t.string :uuid
      t.jsonb  :props_data, default: [], null: false
      t.jsonb  :links_data, default: [], null: false
      t.jsonb  :parts_data, default: [], null: false
    end

    change_table :catalog_controls do |t|
      t.string :uuid
      t.string :control_class
      t.jsonb  :params_data, default: [], null: false
      t.jsonb  :props_data,  default: [], null: false
      t.jsonb  :links_data,  default: [], null: false
      t.jsonb  :parts_data,  default: [], null: false
    end

    # ── Profile tables ──────────────────────────────────────────────
    change_table :profile_documents do |t|
      t.jsonb :back_matter_data, default: [], null: false
    end

    change_table :profile_controls do |t|
      t.boolean :exclude,         default: false, null: false
      t.jsonb   :alters_data,     default: [], null: false
      t.jsonb   :additions_data,  default: [], null: false
    end

    # ── CDEF tables ─────────────────────────────────────────────────
    change_table :cdef_documents do |t|
      t.jsonb :back_matter_data, default: [], null: false
      t.jsonb :components_data,  default: [], null: false
    end

    change_table :cdef_controls do |t|
      t.string :uuid
      t.string :component_uuid
      t.jsonb  :props_data,             default: [], null: false
      t.jsonb  :links_data,             default: [], null: false
      t.jsonb  :set_parameters_data,    default: [], null: false
      t.jsonb  :responsible_roles_data, default: [], null: false
      t.jsonb  :statements_data,        default: {}, null: false
    end

    # ── SAR tables ──────────────────────────────────────────────────
    change_table :sar_documents do |t|
      t.jsonb :attestations_data, default: [], null: false
      t.jsonb :back_matter_data,  default: [], null: false
    end

    change_table :sar_results do |t|
      t.jsonb :local_definitions_data, default: {}, null: false
      t.jsonb :attestations_data,      default: [], null: false
    end

    # ── SAP tables (back-matter parity) ─────────────────────────────
    change_table :sap_documents do |t|
      t.jsonb :back_matter_data, default: [], null: false
    end
  end
end
