# frozen_string_literal: true

# 1.18.0-rf #1290 / #1292 — the Boundary filter beside each document list.
#
# The organization's lists (SSPs, POA&Ms, evidence, …) show every boundary the
# user can reach. A "Boundary" group beside the list narrows it to one: "All
# boundaries", each reachable boundary that has records here, with its count,
# and "Not attached" where records with no boundary exist.
#
# ── Where the boundary comes from ─────────────────────────────────────────
#
# Only the URL: `?authorization_boundary_id=<id>` (or `none`), the parameter
# the boundary sidebar and Api::V1 already use. There is no remembered
# selection (owner, revised phase 2 plan): a shared link shows every viewer
# the same list, and the organization's tab shows everything until a boundary
# is picked.
#
# The id is re-checked on every request, because the list starts from the
# user's permission-scoped relation and BoundaryScopedList only NARROWS it: a
# boundary the user cannot reach yields an empty list, exactly like one that
# does not exist, and the filter never names it (it is looked up in
# AuthorizationBoundary.visible_to, the scope the sidebar lists).
#
# ── Use ───────────────────────────────────────────────────────────────────
#
# A list controller declares its type with `boundary_list :ssp` (a
# BoundaryScopedList type) and calls `build_boundary_filter(scope)` with the
# relation it lists BEFORE narrowing by boundary. The view wraps the list in
# shared/_boundary_filter_layout. Only with SPARC_NAV_SHELL on; otherwise
# `boundary_filter` is nil and every list renders as before.
#
# NIST SP 800-53 Rev 5:
#   AC-3 Access Enforcement — counts and names only what the user may list;
#        a URL naming an unreachable boundary narrows to nothing.
#   AC-4 Information Flow Enforcement — one boundary's records stay in its list.
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
module BoundaryListFilter
  extend ActiveSupport::Concern

  # `selected` is :all, :none, :boundary (with `boundary`) or :unavailable (an
  # id the user cannot reach, or that does not exist; never told apart).
  Filter = Struct.new(:type, :selected, :boundary, :total, :entries, :none_count, :query, keyword_init: true) do
    def param = BoundaryScopedList::PARAM.to_s

    def all_params = query.except(param, "page")

    def boundary_params(boundary) = all_params.merge(param => boundary.id.to_s)

    def none_params = all_params.merge(param => BoundaryScopedList::NONE)

    # "Not attached" is offered where such records exist, or when chosen.
    def show_none? = none_count.positive? || selected == :none
  end

  Entry = Struct.new(:boundary, :count, :current, keyword_init: true)

  included do
    class_attribute :boundary_list_type, instance_writer: false, default: nil
    helper_method :boundary_filter
  end

  class_methods do
    def boundary_list(type)
      raise ArgumentError, "unknown boundary list #{type.inspect}" unless BoundaryScopedList::RULES.key?(type)

      self.boundary_list_type = type
    end
  end

  def self.enabled? = SparcConfig.nav_shell?

  private

  def boundary_filter = @boundary_filter

  # A list whose browse query also offers the boundary as a dropdown facet
  # (POA&M, evidence) drops it while the Boundary filter is shown, so the
  # boundary is chosen in one place. The filter form still carries the
  # parameter along (it keeps every query parameter it has no field for), and
  # "Clear all" keeps it, as the column is not one of the row's filters.
  def boundary_facet_keys(keys)
    boundary_filter ? Array(keys) - [ BoundaryScopedList::PARAM ] : Array(keys)
  end

  def without_boundary_field(fields)
    boundary_filter ? fields.reject { |f| f[:key] == BoundaryScopedList::PARAM } : fields
  end

  # `scope`: the list's permission-scoped relation, before boundary narrowing.
  def build_boundary_filter(scope)
    return unless BoundaryListFilter.enabled? && boundary_list_type

    type = boundary_list_type
    value = params[BoundaryScopedList::PARAM].to_s
    reachable = AuthorizationBoundary.visible_to(current_user).order(:name).to_a

    selected, boundary =
      if value.blank? then [ :all, nil ]
      elsif value == BoundaryScopedList::NONE then [ :none, nil ]
      elsif (found = reachable.find { |b| b.id.to_s == value }) then [ :boundary, found ]
      else [ :unavailable, nil ]
      end

    counts = BoundaryScopedList.counts_by_boundary(type, scope)
    entries = reachable.filter_map do |b|
      count = counts[b.id]
      next unless count.positive? || b == boundary

      Entry.new(boundary: b, count: count, current: b == boundary)
    end
    none_count = BoundaryScopedList.unattached?(type) ? BoundaryScopedList.narrow(type, BoundaryScopedList.base(scope), BoundaryScopedList::NONE).count : 0

    @boundary_filter = Filter.new(type: type, selected: selected, boundary: boundary,
                                  total: BoundaryScopedList.base(scope).count, entries: entries,
                                  none_count: none_count, query: request.query_parameters)
  end
end
