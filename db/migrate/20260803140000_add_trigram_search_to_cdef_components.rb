# #887 — make the browser search index-backed.
#
# Search has to reach values held in array columns (region ids, control ids,
# capabilities, check ids), and it has to match partially: `us-east` must find
# `us-east-1`, `AC-2` must find `AC-2.1`. Exact array membership cannot do that,
# so the query was `ILIKE` over `unnest(...)` — which no GIN index can serve,
# leaving a sequential scan of every component row on every keystroke.
#
# A trigram index fixes that, but it indexes a column, not an expression over
# seven arrays. So everything searchable is denormalized into one text column
# and the trigram index goes on that.
#
# Not a generated column: PostgreSQL rejects `array_to_string` in one
# ("generation expression is not immutable"). CdefComponentIndexer maintains it
# instead, which is safe because the indexer replaces a document's rows
# wholesale and is the only writer.
class AddTrigramSearchToCdefComponents < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_column :cdef_components, :search_blob, :text

    # gin_trgm_ops serves ILIKE '%term%'. Terms shorter than three characters
    # cannot form a trigram and still fall back to a scan — acceptable, since
    # a one or two character query is not selective anyway.
    add_index :cdef_components, :search_blob,
              using: :gin, opclass: :gin_trgm_ops,
              name: "idx_cdef_components_search_trgm"
  end

  def down
    remove_index :cdef_components, name: "idx_cdef_components_search_trgm"
    remove_column :cdef_components, :search_blob
    # pg_trgm is left enabled: dropping an extension other objects may come to
    # rely on is not something a table migration should decide.
  end
end
