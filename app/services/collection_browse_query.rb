# frozen_string_literal: true

# #908 — one definition of "what does filtering this collection mean".
#
# `CdefBrowseQuery` (#887) established the shape: a query object both the web
# screen and its Api::V1 sibling go through, so a facet cannot be added to one
# surface and quietly missed on the other. Four more screens need the same
# thing, and the parts that are genuinely shared are not the facets — they are
# the mechanics around them:
#
#   * applying a plain `where(column => value)` narrowing
#   * building each dropdown's choices FROM THE LOADED DATA rather than a
#     hardcoded enum, so the list cannot drift as new OSCAL versions arrive
#     (the corpus already spans 1.1.2 / 1.1.3 / 1.2.1 across documents that
#     ship together — see #908)
#   * hiding a facet whose value set has cardinality 1, because a dropdown
#     offering one choice is noise
#   * date ranges, which are two params and two chips rather than one
#
# So those live here and subclasses declare only what is screen-specific.
#
# `CdefBrowseQuery` is deliberately NOT retrofitted onto this. Its facets
# resolve through the component index and fold back to documents — a genuinely
# different mechanic from `where(column => value)` — and rewriting a working
# shared query object to inherit from a new base is a refactor this issue did
# not ask for.
#
# ── Where the choices come from ─────────────────────────────────────────────
#
# From the BASE scope, before any narrowing. Deriving them from the filtered
# scope would empty every other dropdown as soon as one filter was applied,
# which reads as broken. The cost is that some combinations return nothing —
# which is honest, and the empty state already says so.
class CollectionBrowseQuery
  class_attribute :facet_definitions, default: {}, instance_writer: false

  class << self
    # Declare a facet.
    #
    #   facet :oscal_version, label: "OSCAL version"
    #   facet :baseline_level, label: "Baseline"
    #   facet :uploaded_by_user_id, label: "Added by", choices: ->(scope) { ... }
    #   facet :created, label: "Created", type: :date, column: :created_at
    #
    # `choices` is for facets whose stored value is not what a person should
    # read — a user FK, say. It receives the base scope and returns
    # [[label, value], ...].
    #   facet :control_id, label: "Control", type: :text,
    #         narrow: ->(rel, value) { rel.where(id: ...) }
    #
    # `narrow` is the escape hatch for a facet that is not a column on this
    # table — a value reached through a join, say. Without it a screen with one
    # such facet would have to abandon the shared mechanics for all of them.
    def facet(key, label:, type: :select, column: nil, choices: nil, narrow: nil)
      self.facet_definitions = facet_definitions.merge(
        key => { key: key, label: label, type: type, column: column || key,
                 choices: choices, narrow: narrow }
      )
    end

    # The param names this screen treats as filters.
    #
    # A date facet occupies TWO params — `<key>_from` and `<key>_to` — because
    # each end is independently removable. `active_facets` renders one chip per
    # param, so a user who set both can drop either without losing the other.
    def facet_params
      facet_definitions.values.flat_map { |d| d[:type] == :date ? date_params(d[:key]) : [ d[:key] ] }
    end

    def facet_labels
      facet_definitions.values.each_with_object({}) do |d, labels|
        if d[:type] == :date
          from, to = date_params(d[:key])
          labels[from] = "#{d[:label]} from"
          labels[to]   = "#{d[:label]} to"
        else
          labels[d[:key]] = d[:label]
        end
      end
    end

    def date_params(key)
      [ :"#{key}_from", :"#{key}_to" ]
    end

    # The collection this query narrows, when the caller does not supply one.
    #
    # Boundary-scoped screens DO supply one — `boundary_scoped_relation` decides
    # what a user may see, and that must never be re-derived here where it could
    # be forgotten.
    def queries(model, order: nil)
      @model = model
      @order = order
    end

    def default_scope_for_query
      scope = @model.all
      @order ? scope.order(@order) : scope
    end
  end

  def initialize(params, scope: self.class.default_scope_for_query)
    @params = params
    @base = scope
  end

  # The narrowed collection: free-text search AND every active facet.
  def records
    apply_facets(apply_search(@base))
  end

  # The facets actually in play, for the API to echo back so a caller can tell
  # what narrowed the result set without re-parsing the query string.
  def applied_facets
    self.class.facet_params.index_with { |key| @params[key].presence }.compact
  end

  # What the filter form should draw: one entry per facet that is worth
  # offering. Cardinality-1 select facets are dropped — with one exception, a
  # facet the user has ALREADY set, which must stay visible or the control that
  # set it disappears while its effect remains.
  def filter_fields
    self.class.facet_definitions.values.filter_map do |definition|
      next date_field(definition) if definition[:type] == :date

      if definition[:type] == :text
        next { key: definition[:key], label: definition[:label], type: :text,
               value: @params[definition[:key]] }
      end

      choices = choices_for(definition)
      next if choices.size < 2 && @params[definition[:key]].blank?

      { key: definition[:key], label: definition[:label], type: :select,
        choices: choices, value: @params[definition[:key]] }
    end
  end

  private

  def date_field(definition)
    from, to = self.class.date_params(definition[:key])
    { key: definition[:key], label: definition[:label], type: :date,
      from_key: from, to_key: to,
      from_value: @params[from], to_value: @params[to] }
  end

  # Distinct non-blank values, as [label, value] pairs, ordered for a human.
  #
  # `reorder(nil)` is load-bearing, not tidying. Every index scope carries a
  # display order (`created_at DESC`, `name`), and Postgres rejects
  # `SELECT DISTINCT ... ORDER BY <column not in the select list>`. The screen's
  # order is meaningless for a list of distinct values anyway — these are sorted
  # for reading, not shown in record order.
  def choices_for(definition)
    unordered = @base.reorder(nil)
    return Array(definition[:choices].call(unordered)) if definition[:choices]

    unordered.where.not(definition[:column] => [ nil, "" ])
             .distinct
             .pluck(definition[:column])
             .sort
             .map { |value| [ value, value ] }
  end

  # Screens override when search means more than the model's own scope.
  def apply_search(scope)
    term = @params[:q].presence
    return scope if term.blank?

    scope.search_text(term)
  end

  def apply_facets(scope)
    self.class.facet_definitions.each_value do |definition|
      scope = definition[:type] == :date ? apply_date(scope, definition) : apply_select(scope, definition)
    end
    scope
  end

  def apply_select(scope, definition)
    value = @params[definition[:key]].presence
    return scope if value.blank?
    return definition[:narrow].call(scope, value) if definition[:narrow]

    scope.where(definition[:column] => value)
  end

  # An unparseable date is ignored rather than raising or returning nothing:
  # a hand-edited query string should not 500, and returning zero rows for
  # `?created_from=banana` would look like a real empty result.
  def apply_date(scope, definition)
    from_key, to_key = self.class.date_params(definition[:key])
    column = definition[:column]

    if (from = parse_date(@params[from_key]))
      scope = scope.where(column => from.beginning_of_day..)
    end
    if (to = parse_date(@params[to_key]))
      # Inclusive of the chosen day: a user picking "to 3 March" means through
      # the end of 3 March, not up to midnight at its start.
      scope = scope.where(column => ..to.end_of_day)
    end
    scope
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue Date::Error
    nil
  end
end
