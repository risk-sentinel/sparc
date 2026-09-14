# #887 — one row per CDEF component, denormalized for the browser.
#
# The dimensions the browser filters on are scattered across the OSCAL: some in
# component `props`, some only reachable by resolving `links[rel=provided-by]`
# into a *different* file (aws_regions.oscal.json), and the derived NIST ids in
# `cdef_control_fields` as EAV rows keyed by field_name.
#
# Resolving that per query does not hold up: the corpus is 230 documents / 902
# controls before org content, and a control-id facet would mean an EAV join
# with a field_name predicate on every keystroke. So the shape is computed once
# at import and read directly here.
#
# Everything stored here is derived from the source document. Nothing is
# authored, so a rebuild is always safe and the table can be dropped and
# regenerated from the CDEFs.
class CreateCdefComponents < ActiveRecord::Migration[8.1]
  def change
    create_table :cdef_components do |t|
      t.references :cdef_document, null: false, foreign_key: true

      # Identity within the source document.
      t.string :component_uuid, null: false
      t.string :title
      t.string :component_type          # service | software | region | validation | …
      t.text   :description
      t.text   :purpose

      # AWS props (ns http://aws.amazon.com/ns/oscal), absent on non-AWS content.
      t.string :service_id
      t.string :availability            # REGIONAL | ZONAL | SUBZONAL
      t.string :lifecycle_stage         # generally-available | …

      # Resolved from links[rel=provided-by].resource-fragment against the
      # regions CDEF. `partitions` is derived from the region-id prefix —
      # us-gov-* => aws-us-gov, cn-* => aws-cn, otherwise aws.
      t.string :region_ids, array: true, default: [], null: false
      t.string :partitions, array: true, default: [], null: false

      # Does this component contribute to continuous assessment, or is it
      # documentation only? Config Rule components carry ConfigRuleId.
      t.boolean :has_checks, null: false, default: false
      t.integer :check_count, null: false, default: 0

      # Control coverage, kept in two distinct layers on purpose: `native` is
      # what the upstream author actually asserted, `enriched` is what SPARC
      # derived through its mapping layer. Merging them would let a derived
      # mapping be read as an upstream assertion.
      t.string :native_control_ids, array: true, default: [], null: false
      t.string :enriched_control_ids, array: true, default: [], null: false
      t.string :mapping_sources, array: true, default: [], null: false  # aws_direct | via_config_rule

      # Lets a rebuild skip components whose source has not moved.
      t.string :content_hash

      t.timestamps
    end

    add_index :cdef_components, [ :cdef_document_id, :component_uuid ],
              unique: true, name: "idx_cdef_components_doc_uuid"
    add_index :cdef_components, :component_type
    add_index :cdef_components, :service_id
    add_index :cdef_components, :has_checks, where: "has_checks = true",
              name: "idx_cdef_components_with_checks"

    # GIN for the array facets — these are all `&&` / `@>` membership queries.
    add_index :cdef_components, :partitions, using: :gin
    add_index :cdef_components, :region_ids, using: :gin
    add_index :cdef_components, :native_control_ids, using: :gin
    add_index :cdef_components, :enriched_control_ids, using: :gin
  end
end
