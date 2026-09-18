# #887 — "what does this component actually do?"
#
# The owner's framing: an Okta CDEF should be findable as *MFA*. That is a
# functional capability, not the OSCAL `capabilities` construct — which is
# absent from all 230 upstream AWS files and would stay empty for them.
#
# Two columns rather than one, for the same reason native and enriched control
# ids are kept apart: a capability the author DECLARED is a different kind of
# claim from one SPARC INFERRED, and collapsing them lets an inference be read
# as an assertion.
#
#   declared_capabilities — from `props[name=capability]` on the component.
#                           This is how an org-authored or custom CDEF states
#                           its own capability and gets the same searchable
#                           fields as the AWS corpus.
#   derived_capabilities  — inferred from the control ids the component covers,
#                           through an explicit, small, documented map.
#
# check_ids carries the automated-check identifiers (AWS Config Rule ids today)
# so "what can automatically check this?" is answerable, not just "does it have
# checks".
class AddCapabilitiesToCdefComponents < ActiveRecord::Migration[8.1]
  def change
    add_column :cdef_components, :declared_capabilities, :string, array: true, default: [], null: false
    add_column :cdef_components, :derived_capabilities, :string, array: true, default: [], null: false
    add_column :cdef_components, :check_ids, :string, array: true, default: [], null: false

    add_index :cdef_components, :declared_capabilities, using: :gin
    add_index :cdef_components, :derived_capabilities, using: :gin
    add_index :cdef_components, :check_ids, using: :gin
  end
end
