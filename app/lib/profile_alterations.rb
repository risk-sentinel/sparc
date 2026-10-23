# frozen_string_literal: true

# ProfileAlterations — applies a profile's stored `alters` to one control in
# the OSCAL JSON model (#1252). The one place an alter takes effect: the
# resolved catalog (and so SSP generation, which reads it) and the requirement
# text both call it, so a part a profile removes is gone from both and a part it
# adds appears in both.
#
# Per the OSCAL profile resolution specification:
#
#   remove   every param, prop, link and part in the control, at any depth,
#            matching ALL the criteria given: by-name, by-class, by-id,
#            by-ns, by-item-name (the kind: param, prop, link, part)
#   add      title, params, props, links and parts, placed by `position`
#            relative to `by-id` (the control itself when by-id is absent):
#              starting / ending   first / last among the target's children
#              before / after      immediately before / after the target
#
# Removes are applied before adds, so an alter can replace a part.
#
# A `by-id` that names nothing in the control places nothing, and is reported
# in #unplaced rather than appended somewhere else: a part in the wrong place
# would put a requirement under the wrong statement.
#
# NIST 800-53: PL-11 (baseline tailoring), CM-2.
class ProfileAlterations
  ITEM_KEYS = { "param" => "params", "prop" => "props", "link" => "links", "part" => "parts" }.freeze
  DEFAULT_POSITION = "ending"
  BY_ITEM_NAME = "by-item-name"
  BY_NAME = "by-name"
  BY_CLASS = "by-class"

  attr_reader :unplaced

  # @param alters [Array<Hash>] the control's alters (OSCAL JSON)
  # @param resolve [#call, nil] applied to every added prose string, so an
  #   added part's {{ insert: param }} resolves like the catalog's own
  def initialize(alters, resolve: nil)
    @alters   = Array(alters)
    @resolve  = resolve
    @unplaced = []
  end

  def empty? = @alters.empty?

  # Applies every alter to `control` (an OSCAL control hash) in place.
  def apply!(control)
    @alters.each do |alter|
      Array(alter["removes"]).each { |remove| remove!(control, remove) }
      Array(alter["adds"]).each { |add| add!(control, add) }
    end
    control
  end

  private

  # ── Removes ────────────────────────────────────────────────────────────

  def remove!(node, remove)
    ITEM_KEYS.each do |kind, key|
      next unless node[key].is_a?(Array)

      node[key].reject! { |item| matches?(item, kind, remove) }
      node.delete(key) if node[key].empty?
    end
    Array(node["parts"]).each { |part| remove!(part, remove) }
  end

  def matches?(item, kind, remove)
    return false if remove[BY_ITEM_NAME].present? && remove[BY_ITEM_NAME] != kind
    return false if remove[BY_NAME].present? && item["name"] != remove[BY_NAME]
    return false if remove[BY_CLASS].present? && item["class"] != remove[BY_CLASS]
    return false if remove["by-ns"].present? && item["ns"] != remove["by-ns"]
    return false if remove["by-id"].present? && item_id(item, kind) != remove["by-id"]

    remove.slice(BY_NAME, BY_CLASS, "by-id", "by-ns", BY_ITEM_NAME).values.any?(&:present?)
  end

  def item_id(item, kind) = kind == "prop" ? item["uuid"] : item["id"]

  # ── Adds ───────────────────────────────────────────────────────────────

  def add!(control, add)
    position = add["position"].presence || DEFAULT_POSITION
    target_id = add["by-id"].presence
    items = additions(add)

    if target_id.nil? || target_id == control["id"]
      control["title"] = add["title"] if add["title"].present? && target_id.nil?
      return insert_children(control, items, position)
    end

    parent, index = locate(control, target_id)
    return @unplaced << target_id if parent.nil?

    target = parent["parts"][index]
    case position
    when "before" then insert_siblings(parent, index, items)
    when "after"  then insert_siblings(parent, index + 1, items)
    else insert_children(target, items, position)
    end
  end

  # [key, items] pairs in OSCAL's member order. Props are excluded: a profile's
  # added props keep their own home (priority column, prop fields).
  def additions(add)
    %w[params links parts].filter_map do |key|
      items = Array(add[key]).map { |item| resolve_prose(item.deep_dup) }
      [ key, items ] if items.any?
    end
  end

  def insert_children(node, items, position)
    items.each do |key, list|
      node[key] ||= []
      position == "starting" ? node[key].unshift(*list) : node[key].concat(list)
    end
  end

  # before/after a part: only parts can be siblings of a part.
  def insert_siblings(parent, index, items)
    items.each do |key, list|
      next insert_children(parent, [ [ key, list ] ], DEFAULT_POSITION) unless key == "parts"

      parent["parts"].insert(index, *list)
    end
  end

  # The part with `id` and the node holding it, searched depth-first.
  def locate(node, id)
    Array(node["parts"]).each_with_index do |part, index|
      return [ node, index ] if part["id"] == id

      found = locate(part, id)
      return found if found.first
    end
    [ nil, nil ]
  end

  def resolve_prose(item)
    return item unless @resolve

    item["prose"] = @resolve.call(item["prose"]) if item["prose"].is_a?(String)
    Array(item["parts"]).each { |part| resolve_prose(part) }
    item
  end
end
