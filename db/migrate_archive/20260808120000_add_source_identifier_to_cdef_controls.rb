# #912 — separate the SOURCE identifier from the NIST reference.
#
# `cdef_controls.control_id` was mixed-vocabulary. A CDEF built from an AWS Labs
# component definition stores Security Hub ids (`IAM.3`); a DISA STIG resolves
# rule -> CCI -> NIST; a plain InSpec profile stores its own control names; an
# OSCAL component definition stores NIST. One column, four vocabularies, and
# nothing could tell them apart.
#
# That made every mechanical operation on the column correct for NIST rows and
# wrong for the rest. #911 had to DISABLE canonicalisation on this model for
# exactly that reason: `ControlId.canonical` encodes NIST numbering, so it
# rewrote `IAM.3` to `iam.3` and broke the Security Hub enrichment lookups.
#
# The split, which the AWS importer already proved in miniature by writing
# `nist_oscal_ids` as a field alongside an untouched `control_id`:
#
#   source_control_id  — exactly as it arrived, never rewritten. Provenance.
#   source_vocabulary  — which framework it came from, so consumers do not have
#                        to infer it from the shape of the string.
#   control_id         — the NIST reference, resolved through the relevant
#                        converter, and therefore safe to canonicalise and join.
#
# Both columns are NULLABLE and no backfill happens here: the data migration is
# deferred (20260808120100) so the container boots immediately, and
# `CdefControl#source_identifier` falls back to the legacy columns throughout
# that window.
class AddSourceIdentifierToCdefControls < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:cdef_controls, :source_control_id)
      add_column :cdef_controls, :source_control_id, :string
    end

    unless column_exists?(:cdef_controls, :source_vocabulary)
      add_column :cdef_controls, :source_vocabulary, :string
    end

    # Scoped to the document, mirroring the existing stig_id index: the question
    # asked in practice is "which row in THIS component definition carries this
    # source identifier", never "which row anywhere".
    unless index_exists?(:cdef_controls, [ :cdef_document_id, :source_control_id ],
                         name: "index_cdef_controls_on_document_and_source_control_id")
      add_index :cdef_controls, [ :cdef_document_id, :source_control_id ],
                name: "index_cdef_controls_on_document_and_source_control_id"
    end

    # Not unique: a benchmark may legitimately carry the same source identifier
    # on more than one row, and a unique index here would abort an import over
    # data SPARC does not control.
    unless index_exists?(:cdef_controls, :source_vocabulary,
                         name: "index_cdef_controls_on_source_vocabulary")
      add_index :cdef_controls, :source_vocabulary,
                name: "index_cdef_controls_on_source_vocabulary"
    end
  end
end
