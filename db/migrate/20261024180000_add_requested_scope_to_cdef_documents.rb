# frozen_string_literal: true

# #1275 — the wider scope a CDEF's author asked for when submitting it for
# review: organization-wide ("global") or instance-wide ("instance").
#
# Nearly anyone may author a CDEF on their boundary; making it available more
# widely is an approval, decided at the tier it will reach (owner,
# 2026-10-24). The request is held here while the CDEF is pending and applied
# by CdefScopeService when it is approved. NULL means the CDEF keeps the scope
# it has.
#
# Existing rows need no backfill: none has asked for a wider scope.
class AddRequestedScopeToCdefDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :cdef_documents, :requested_scope, :string
    add_check_constraint :cdef_documents, "requested_scope IN ('global', 'instance')",
                         name: "cdef_documents_requested_scope_values"
  end
end
