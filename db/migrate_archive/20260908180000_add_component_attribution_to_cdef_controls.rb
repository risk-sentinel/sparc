# frozen_string_literal: true

# #1088 items 4 and 5 — one missing structure behind both.
#
# OSCAL nests a component definition's controls three deep:
#
#   component-definition
#     components[]                        <- WHICH component asserts it
#       control-implementations[]         <- against WHICH catalog or profile
#         implemented-requirements[]      <- the control
#
# `CdefJsonParserService` walks all three and keeps only the innermost, so
# `cdef_controls` rows land on the DOCUMENT with no record of which component
# declared them or which source they were claimed against. Two consequences the
# owner hit on the same screen:
#
#   ITEM 5. The AWS Elastic Beanstalk CDEF has four components — one `service`
#   carrying the regions and partitions, and three `software` components that
#   are AWS CONFIG RULES, i.e. the checks. The service declares
#   ELASTICBEANSTALK.1/2/3 and each config rule re-declares one of them, so the
#   flattened list held 6 rows for 3 controls with nothing to say why. They are
#   not nested CDEFs and not related services: they are checks, and the page had
#   no way to say so.
#
#   ITEM 4. `control-implementations[].source` is REQUIRED by the OSCAL schema
#   and documented as "a reference to an OSCAL catalog or profile". It is an
#   ARRAY, so one CDEF legitimately implements controls from several catalogs
#   and several profiles at once — R4 and R5 together, for instance. SPARC threw
#   the source away on import and re-synthesised a single one on export from the
#   `profile_document_id` foreign key, which can only ever name one. A CDEF that
#   arrived with two sources exported with one, silently reattributing controls
#   to a catalog that never claimed them.
#
# ── Why strings and not foreign keys ──────────────────────────────────────
#
# `component_uuid` is the OSCAL uuid, NOT a reference to `cdef_components.id`.
# `CdefComponentIndexer#index!` is `delete_all` + `insert_all!` on every
# re-index, so every primary key changes; an FK would dangle on the next import
# of the same document. The OSCAL uuid is stable by construction and is what the
# exported document actually references.
#
# `implementation_source` is the source URI verbatim. Resolving it to a
# ProfileDocument or ControlCatalog is a lookup the exporter can do when it
# matters; storing the string means a source SPARC has no local record of — an
# external catalog, another instance's profile — round-trips unharmed instead of
# being dropped for failing to resolve.
class AddComponentAttributionToCdefControls < ActiveRecord::Migration[8.1]
  def change
    add_column :cdef_controls, :component_uuid, :string
    add_column :cdef_controls, :implementation_source, :string
    add_column :cdef_controls, :implementation_description, :text

    # Export groups by (component, source) and the show page groups by
    # component, so both reads are covered by one composite index.
    add_index :cdef_controls, [ :cdef_document_id, :component_uuid ],
              name: "index_cdef_controls_on_document_and_component"
    add_index :cdef_controls, [ :cdef_document_id, :implementation_source ],
              name: "index_cdef_controls_on_document_and_source"
  end
end
