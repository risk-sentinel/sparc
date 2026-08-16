# #944 — give a component definition's OSCAL fields somewhere to be entered.
#
# `OscalComponentDefinitionExportService#build_component` did not read these
# from anywhere; it HARDCODED them:
#
#   "type"        => "software"
#   "title"       => @document.name
#   "description" => @document.description || "Imported component definition"
#   "source"      => determine_source          # a cdef_type lookup, else a
#                                              # synthesised sparc.local URL
#   "description" => "Controls from … component definition: …"
#
# So every field NIST's simple-component-definition tutorial calls required had
# nowhere to be entered, and every CDEF SPARC exported claimed to be software
# regardless of what it actually was. That is why #944 reports the document type
# where authoring matters most as the one that cannot be authored.
#
# All columns are nullable and the exporter falls back to exactly the values it
# used before, so existing documents export byte-identically until someone
# edits them. A NOT NULL default would have rewritten the meaning of every
# imported CDEF in place.
class AddComponentAuthoringFieldsToCdefDocuments < ActiveRecord::Migration[8.1]
  COLUMNS = {
    # OSCAL `components[].type`. The `defined-component` enum in the baked-in
    # v1.1.2 schema is: interconnection, software, hardware, service, policy,
    # physical, process-procedure, plan, guidance, standard, validation.
    # Hardcoded to "software" before this.
    component_type: :string,
    # OSCAL `components[].title` / `.description`. Distinct from the DOCUMENT's
    # name and description: "AWS S3 (OSCAL 1.1.2)" is a reasonable file name and
    # a poor component title, and #466 already shows the two diverging.
    component_title: :string,
    component_description: :text,
    # OSCAL `control-implementations[].source` — the catalog or profile whose
    # controls are being implemented. The fallback synthesises a
    # `https://sparc.local/component-definitions/<id>` URL that resolves to
    # nothing and leaks the database primary key.
    control_implementation_source: :string,
    control_implementation_description: :text
  }.freeze

  def up
    COLUMNS.each do |name, type|
      next if column_exists?(:cdef_documents, name)

      add_column :cdef_documents, name, type
    end
  end

  def down
    COLUMNS.each_key do |name|
      next unless column_exists?(:cdef_documents, name)

      remove_column :cdef_documents, name
    end
  end
end
