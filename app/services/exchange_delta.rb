# frozen_string_literal: true

require "json"

# What changed between two deliveries of the same exchanged document (#1354).
#
# A connection pulls (or a person uploads) a FedRAMP, OSCAL, HDF or XCCDF
# document. Before it takes effect, SPARC compares it with the stream's last
# accepted version and classes every change:
#
#   regression  — a new failure, a new vulnerability, an implementation status
#                 moving down, a required field going blank, a class change...
#   improvement — the reverse of each of those.
#   neutral     — anything else that changed. Neutral is NOT safe to accept
#                 unseen: it is a change nobody has classed.
#
# Auto-accept (owner decision, 2026-11-20): only a version with no changes, or
# with improvements only. A regression or a neutral change waits for a person,
# and so does a stream's first version (there is nothing to compare it with).
#
#   delta = ExchangeDelta.compare(format: "hdf", document_type: "results",
#                                 before: accepted_bytes, after: new_bytes)
#   delta.auto_acceptable?   # => false
#   delta.counts             # => { regression: 1, improvement: 0, neutral: 2 }
#   delta.changes.first.summary  # => "AC-2: passed → failed"
#
# Pure Ruby: no database and no network. The one external call is the pinned
# hdf CLI, to convert a legacy HDF v2 document up to v3 (as ingest does).
# The output is bounded (MAX_CHANGES, regressions kept first) so a huge
# document cannot blow up a review page; `counts` always covers every change.
#
# NIST SP 800-53: CA-7 (continuous monitoring — what changed between
# deliveries is the monitoring signal), CA-2 (control assessments — assessment
# results are compared result by result, so a new failure is never hidden in a
# re-delivery), SI-4 (system monitoring — a regression always reaches a person).
class ExchangeDelta
  # A document that could not be read for comparison. The caller still gets a
  # Result: one neutral change saying why, so the version waits for a person.
  class NotComparable < StandardError; end

  KINDS = %i[regression improvement neutral].freeze
  MAX_CHANGES = 2_000
  MAX_VALUE_CHARS = 500

  Change = Data.define(:kind, :key, :summary, :before, :after)

  Result = Data.define(:changes, :counts, :first_version, :truncated) do
    def first_version? = first_version
    def truncated? = truncated
    def total = counts.values.sum

    # Owner decision (#1354, 2026-11-20): no changes, or improvements only.
    # A first version always gets a person's look.
    def auto_acceptable? = !first_version && counts[:regression].zero? && counts[:neutral].zero?

    def as_json(*)
      { first_version: first_version, auto_acceptable: auto_acceptable?, truncated: truncated,
        counts: counts, changes: changes.map { |c| c.to_h.merge(kind: c.kind.to_s) } }
    end
  end

  # Collects changes: counts every one, keeps at most `limit`, regressions first.
  class Changes
    def initialize(limit: MAX_CHANGES)
      @limit = limit
      @kept = KINDS.index_with { [] }
      @counts = KINDS.index_with { 0 }
    end

    def add(kind, key, summary, before: nil, after: nil)
      raise ArgumentError, "unknown change kind #{kind.inspect}" unless KINDS.include?(kind)

      @counts[kind] += 1
      list = @kept[kind]
      list << Change.new(kind: kind, key: key.to_s, summary: summary.to_s,
                         before: ExchangeDelta.stored(before), after: ExchangeDelta.stored(after)) if list.size < @limit
      nil
    end

    def regression(key, summary, **values) = add(:regression, key, summary, **values)
    def improvement(key, summary, **values) = add(:improvement, key, summary, **values)
    def neutral(key, summary, **values) = add(:neutral, key, summary, **values)

    def to_result(first_version: false)
      kept = KINDS.flat_map { |k| @kept[k] }.first(@limit)
      Result.new(changes: kept, counts: @counts.dup, first_version: first_version,
                 truncated: @counts.values.sum > kept.size)
    end
  end

  # @param format [String] "hdf", "oscal", "fedramp" or "xccdf" (DocumentValidationService#format)
  # @param document_type [String, nil] DocumentValidationService#document_type
  # @param before [String, nil] the stream's last accepted version, or nil for none
  # @param after [String] the version just received
  # @param hdf_runner [HdfRunner, nil] injected for specs
  # @return [Result]
  def self.compare(format:, document_type:, before:, after:, hdf_runner: nil)
    raise ArgumentError, "after is required" if after.nil?

    changes = Changes.new
    return changes.to_result(first_version: true) if before.nil?
    return changes.to_result if before.to_s.b == after.to_s.b

    begin
      comparer(format.to_s, document_type.to_s, hdf_runner).compare(before.to_s, after.to_s, changes)
    rescue NotComparable => e
      changes.neutral("document", "Not compared: #{e.message}")
    end
    changes.to_result
  end

  def self.comparer(format, document_type, hdf_runner)
    case format
    when "hdf" then HdfComparer.new(runner: hdf_runner)
    when "oscal" then OscalComparer.new
    when "fedramp" then FedrampComparer.new(document_type)
    when "xccdf" then XccdfComparer.new
    else GenericComparer.new
    end
  end

  # ── shared helpers ───────────────────────────────────────────────────

  def self.xml?(raw) = raw.lstrip.start_with?("<")

  def self.parse_json(raw)
    JSON.parse(raw)
  rescue JSON::ParserError => e
    raise NotComparable, "not valid JSON (#{e.message.lines.first.to_s.strip.truncate(120)})"
  end

  # A value as a reviewer reads it in a one-line summary.
  def self.brief(value)
    case value
    when nil then "(none)"
    when String then value.strip.empty? ? "(blank)" : value.squish.truncate(80)
    when Hash then "(object)"
    when Array then "(#{value.size} #{value.size == 1 ? 'item' : 'items'})"
    else value.to_s
    end
  end

  # A value as a Change carries it: scalars as they are (text bounded), and a
  # brief for an object or list.
  def self.stored(value)
    case value
    when String then value.truncate(MAX_VALUE_CHARS)
    when Hash, Array then brief(value)
    else value
    end
  end

  # Any format SPARC has no specific rules for: JSON compared field by field,
  # anything else byte-wise. Every change is neutral.
  class GenericComparer
    def compare(before, after, changes)
      if ExchangeDelta.xml?(before) || ExchangeDelta.xml?(after)
        changes.neutral("document", "Document changed (compared byte-wise)")
      else
        JsonDiff.neutral_changes(ExchangeDelta.parse_json(before), ExchangeDelta.parse_json(after), changes)
      end
    end
  end
end
