# frozen_string_literal: true

# #908 — filtering the control-catalog index.
#
# The issue proposed OSCAL version, revision and framework. The first two are
# real columns. **Framework is not a field anywhere** — in the NIST catalogs we
# hold it exists only inside the title string ("...Special Publication 800-53...")
# and the filename, so faceting it would mean deriving and persisting it at
# import. That is a separate piece of work with a migration behind it, and it is
# deliberately not faked here: a dropdown built by regexing titles at request
# time would be wrong the first time a catalog arrived with a different title
# convention.
class CatalogBrowseQuery < CollectionBrowseQuery
  queries ControlCatalog, order: :name

  # `version` is the catalog's own revision ("5.2.0", "Rev 4"), which is what a
  # user means by "revision" on this screen — distinct from oscal_version, the
  # schema the file was written against. Both are offered because a single
  # package legitimately spans several of the latter.
  facet :oscal_version,    label: "OSCAL version"
  facet :version,          label: "Revision"
  facet :source,           label: "Source"
  facet :lifecycle_status, label: "Status"

  # The file-import status (pending/processing/completed/failed), which the
  # Api::V1 endpoint has always accepted as `?status=` — so it has to stay a
  # filter or existing callers break. It is rarely interesting on the screen,
  # where nearly every catalog is `completed`; the cardinality-1 rule drops the
  # dropdown in that case without anyone having to decide screen by screen.
  facet :status, label: "Import status"
end
