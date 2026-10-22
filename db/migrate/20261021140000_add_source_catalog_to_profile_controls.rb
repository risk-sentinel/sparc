# frozen_string_literal: true

# #1234 — a profile can import more than one catalog (NIST SP 800-53 plus an
# organization's own controls), and each selected control comes from one of
# them. `profile_documents.control_catalog_id` stays the profile's primary
# catalog; this records, per control, the catalog its import resolved to, so
# titles, export imports and resolution read the right one. Nullable: an
# import that matched no loaded catalog leaves its controls unlinked, and
# every profile imported before this has none (the primary catalog applies).
class AddSourceCatalogToProfileControls < ActiveRecord::Migration[8.1]
  def change
    add_reference :profile_controls, :source_catalog,
                  foreign_key: { to_table: :control_catalogs, on_delete: :nullify },
                  index: true, null: true
  end
end
