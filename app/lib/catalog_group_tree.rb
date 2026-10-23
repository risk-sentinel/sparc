# frozen_string_literal: true

# CatalogGroupTree — an OSCAL catalog group's nested groups (#1252), as the
# import walks them, the export rebuilds them and the family page heads them.
#
# OSCAL lets a group hold groups as well as controls, at any depth (NIST's
# example catalog: `s1` → `s1.1` → `s1.1.1`). SPARC keeps one family per
# top-level group; each nested group is recorded in the family's `group_data`
# (its definition, without controls) and each control's `group_id` names the
# nested group it sits in. A nested group with no `id` (OSCAL allows that) is
# keyed by its position, `~1.2`, kept as `key` beside its definition and never
# exported.
module CatalogGroupTree
  # A group's own fields; `controls` are rows and `groups` are recursed.
  FIELDS = %w[id class title params props links parts].freeze

  module_function

  # Controls directly in these groups and in every group below them.
  def control_count(groups)
    Array(groups).sum { |group| Array(group["controls"]).size + control_count(group["groups"]) }
  end

  # What a family records of the top-level group it was imported from.
  def definition(group, path = [])
    nested = Array(group["groups"]).each_with_index.map do |child, index|
      child_def = definition(child, path + [ index + 1 ])
      child_def["key"] = "~#{(path + [ index + 1 ]).join('.')}" if child["id"].blank?
      child_def
    end
    group.slice(*FIELDS).merge(nested.any? ? { "groups" => nested } : {})
  end

  # Yields each control in the group and in its nested groups, with the key of
  # the nested group it sits in (nil for the top-level group itself).
  def each_control(group, key = nil, path = [], &block)
    Array(group["controls"]).each { |control| yield control, key }
    Array(group["groups"]).each_with_index do |child, index|
      child_path = path + [ index + 1 ]
      each_control(child, key_of(child, child_path), child_path, &block)
    end
  end

  # The key a nested group's controls record: its id, or its position.
  def key_of(group, path)
    group["id"].presence || "~#{path.join('.')}"
  end

  # Rows by the key of the nested group they sit in. A row naming a group the
  # family does not record falls back to the family's own group (nil), so it is
  # shown and exported rather than lost.
  def by_group(rows, group_data)
    known = sections(group_data).to_set { |section| section[:key] }
    rows.group_by { |row| known.include?(row.group_id) ? row.group_id : nil }
  end

  # Nested groups in file order, depth first: [{key:, title:, depth:}].
  def sections(group_data)
    walk = lambda do |groups, depth|
      Array(groups).flat_map do |group|
        [ { key: group["key"] || group["id"], title: group["title"], depth: depth } ] + walk.call(group["groups"], depth + 1)
      end
    end
    walk.call(group_data.to_h["groups"], 1)
  end
end
