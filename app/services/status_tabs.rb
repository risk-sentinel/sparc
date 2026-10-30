# frozen_string_literal: true

# 1.18.0-rf #1299 — the status tabs above a collection, with counts.
#
# A tab is a saved filter, not a new query path: each one names the params it
# sets (`lifecycle_status=published`, `approval_status=approved`), and a click
# is a plain link to the same list with those params. The list narrows through
# whatever already reads them — the screen's browse query, or `narrow` below
# for screens whose filter is new — so a tab and a hand-typed URL can never
# disagree.
#
# Counts come from `base`: the list with every OTHER filter applied (boundary,
# search, facets) and none of the tabs' own params. So "Draft 3" means "3 of
# what you are looking at are drafts", and the counts still add up after a
# search.
#
#   tabs = StatusTabs.lifecycle(base: scope, params: params)
#   scope = tabs.narrow(scope)          # only where nothing else reads the param
class StatusTabs
  Tab = Data.define(:label, :params, :count, :current)

  LIFECYCLE = [
    [ "Started",   { "lifecycle_status" => "started" } ],
    [ "Draft",     { "lifecycle_status" => "in_progress" } ],
    [ "Published", { "lifecycle_status" => "published" } ]
  ].freeze
  LIFECYCLE_KEYS = %w[lifecycle_status].freeze

  # The three lifecycle states every document type shares (Lifecycle).
  def self.lifecycle(base:, params:, extra: [])
    new(base: base, params: params, definitions: LIFECYCLE + extra)
  end

  # Catalogs add Approved (Approvable) to the lifecycle states.
  CATALOG_EXTRA = [ [ "Approved", { "approval_status" => "approved" } ] ].freeze

  def self.catalog(base:, params:)
    lifecycle(base: base, params: params, extra: CATALOG_EXTRA)
  end

  # One tab per value of a status column, in the model's own order.
  def self.for_values(column, values, base:, params:, labels: {})
    definitions = values.map { |v| [ labels.fetch(v, v.to_s.humanize), { column.to_s => v.to_s } ] }
    new(base: base, params: params, definitions: definitions)
  end

  attr_reader :keys

  # CDEFs by source (CdefDocument::SOURCES): a tab is `?source=aws`, and the
  # count goes through the same scope the browse query narrows with.
  def self.cdef_source(base:, params:)
    new(base: base, params: params,
        definitions: CdefDocument::SOURCES.map { |kind, label| [ label, { "source" => kind } ] },
        scope_for: ->(rel, tab_params) { rel.with_source(tab_params["source"]) })
  end

  # definitions — [[label, { "param" => "value" }], ...]
  # scope_for   — how a tab's params narrow a relation, when they are not
  #               columns (default: `where(params)`)
  def initialize(base:, params:, definitions:, all_label: "All", scope_for: nil)
    @base = base.reorder(nil)
    @params = params
    @definitions = definitions
    @all_label = all_label
    @scope_for = scope_for || ->(rel, tab_params) { rel.where(tab_params) }
    @keys = definitions.flat_map { |_, p| p.keys }.uniq
  end

  def tabs
    @tabs ||= [ all_tab ] + @definitions.map do |label, tab_params|
      Tab.new(label: label, params: tab_params, count: @scope_for.call(@base, tab_params).count,
              current: current?(tab_params))
    end
  end

  # Narrow by the tabs' params the request carries. Any value narrows, not
  # only a tab's: `?lifecycle_status=bogus` shows an empty list, as the browse
  # queries' `where(column => value)` does, rather than quietly showing
  # everything. Where a screen's browse query also reads the param the
  # condition is repeated — the same `where`, so the tab and the dropdown
  # cannot mean different things. Never touches the counts.
  def narrow(scope)
    given = @keys.select { |k| @params[k].present? }.index_with { |k| @params[k].to_s }
    given.any? ? @scope_for.call(scope, given) : scope
  end

  # The query params a tab links to: the request's, minus every tab's own key
  # and the page number, plus this tab's.
  def link_params(request_params, tab)
    request_params.except(*keys, "page").merge(tab.params)
  end

  private

  def all_tab
    Tab.new(label: @all_label, params: {}, count: @base.count,
            current: @keys.none? { |k| @params[k].present? })
  end

  def current?(tab_params)
    tab_params.all? { |k, v| @params[k].to_s == v.to_s } &&
      (@keys - tab_params.keys).none? { |k| @params[k].present? }
  end
end
