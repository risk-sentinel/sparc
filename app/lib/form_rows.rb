# frozen_string_literal: true

# #1390 — the rows of a repeated form section (oscal-repeater) or an API list,
# as stored: an array of hashes, or the index-keyed hash a form posts
# ({"0" => {...}, "1" => {...}}), reduced to the given keys with each value
# stripped. Blank values are dropped, and rows left empty with them.
#
#   FormRows.normalize({ "0" => { "description" => " Go live ", "x" => "1" } }, %w[description])
#   # => [{ "description" => "Go live" }]
module FormRows
  extend self

  def normalize(rows, keys)
    rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
    rows = rows.values if rows.is_a?(Hash)
    Array(rows).filter_map do |row|
      row = row.to_unsafe_h if row.respond_to?(:to_unsafe_h)
      next unless row.is_a?(Hash)

      row = row.stringify_keys
      keys.to_h { |k| [ k, row[k].to_s.strip ] }.compact_blank.presence
    end
  end
end
