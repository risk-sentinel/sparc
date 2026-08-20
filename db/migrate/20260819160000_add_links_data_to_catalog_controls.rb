# #999 — control-level OSCAL `links` had nowhere to live, so CatalogImportService
# discarded them. Measured against the seeded Rev 5 source catalog: 1191 of 1196
# controls carry links, 5417 links in all — 838 `reference` (into back-matter),
# 3512 `related`, 715 `required`, 166 `incorporated-into` and 34 `moved-to`.
# The last two record where a WITHDRAWN control went, which is not recoverable
# from anything else SPARC stores.
#
# This column keeps them verbatim, so the catalog round-trips. `reference` links
# are ALSO promoted to BackMatterResource rows and ControlBackMatterLink joins,
# because that is what makes an emitted `#uuid` href resolve to a resource the
# exported document actually carries — the column is the archival record, the
# rows are the resolvable index.
#
# Existing rows keep `[]` until their catalog is re-imported; the source file is
# not retained, so there is nothing to backfill from. The seeded catalogs are
# re-imported by the SeedRunner version bump that ships with this change.
class AddLinksDataToCatalogControls < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:catalog_controls, :links_data)

    add_column :catalog_controls, :links_data, :jsonb, default: []
  end
end
