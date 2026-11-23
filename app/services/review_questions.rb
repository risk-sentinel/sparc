# frozen_string_literal: true

# A reviewer's questions to the provider about a received version (#1390 part
# G), each tied to a place in the document: its JSON Pointer, the location as
# a reader says it, a line on what is there (the change or the error), the
# compared values, and the reviewer's own question.
#
# Everything arrives from a form or the API, so it is bounded and kept as
# plain strings; nothing in it is ever rendered as HTML (SI-10).
#
# NIST SP 800-53: SI-10, AU-10 (stored with the decision and its audit event).
module ReviewQuestions
  MAX = 100
  LIMITS = { "pointer" => 1_000, "label" => 300, "detail" => 1_000, "before" => 500, "after" => 500, "question" => 2_000 }.freeze

  extend self

  # [{ "pointer", "label", "detail", "before", "after", "question" }, ...]
  # from a list of hashes or ActionController::Parameters. Entries with no
  # pointer and no question are dropped; the first entry for a pointer wins.
  def normalize(list)
    entries = case list
    when ActionController::Parameters then list.respond_to?(:values) && !list.key?("pointer") ? list.values : [ list ]
    when Hash then list.key?("pointer") || list.key?(:pointer) ? [ list ] : list.values
    else Array(list)
    end

    entries.filter_map { |entry| clean(entry) }.uniq { |q| q["pointer"].presence || q["question"] }.first(MAX)
  end

  def clean(entry)
    entry = entry.to_unsafe_h if entry.respond_to?(:to_unsafe_h)
    return nil unless entry.is_a?(Hash)

    out = LIMITS.keys.to_h { |field| [ field, entry[field] || entry[field.to_sym] ] }
    out = out.transform_values { |v| v.is_a?(String) || v.is_a?(Numeric) || v == true || v == false ? v.to_s.strip : nil }
    out = out.to_h { |field, v| [ field, v&.truncate(LIMITS.fetch(field)).presence ] }.compact
    out["pointer"].present? || out["question"].present? ? out : nil
  end
end
