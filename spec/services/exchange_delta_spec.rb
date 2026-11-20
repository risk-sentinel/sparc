# frozen_string_literal: true

require "rails_helper"

# #1354 — what changed between two deliveries of an exchanged document, and
# whether the new one may be accepted without a person. The per-format rules
# are in spec/services/exchange_delta/*_spec.rb.
RSpec.describe ExchangeDelta do
  def compare(before, after, format: "hdf", document_type: "results")
    described_class.compare(format: format, document_type: document_type,
                            before: before.is_a?(String) || before.nil? ? before : JSON.generate(before),
                            after: after.is_a?(String) ? after : JSON.generate(after))
  end

  let(:doc) { { "a" => 1, "b" => { "c" => "x" } } }

  describe "the result" do
    it "treats a stream's first version as a first version, never auto-accepted" do
      result = compare(nil, doc, format: "other")
      expect(result).to be_first_version
      expect(result.changes).to be_empty
      expect(result).not_to be_auto_acceptable
    end

    it "finds no changes in identical bytes and auto-accepts them" do
      result = compare(JSON.generate(doc), JSON.generate(doc), format: "other")
      expect(result.changes).to be_empty
      expect(result.counts).to eq(regression: 0, improvement: 0, neutral: 0)
      expect(result).not_to be_first_version
      expect(result).to be_auto_acceptable
    end

    it "requires the version just received" do
      expect { described_class.compare(format: "hdf", document_type: nil, before: "{}", after: nil) }
        .to raise_error(ArgumentError)
    end

    it "auto-accepts improvements only, and nothing with a regression or a neutral change" do
      changes = ExchangeDelta::Changes.new
      changes.improvement("k", "better")
      expect(changes.to_result).to be_auto_acceptable

      changes.neutral("n", "something else changed")
      expect(changes.to_result).not_to be_auto_acceptable

      only_regression = ExchangeDelta::Changes.new
      only_regression.regression("r", "worse")
      expect(only_regression.to_result).not_to be_auto_acceptable
    end

    it "keeps at most the limit, regressions first, and counts every change" do
      changes = ExchangeDelta::Changes.new(limit: 3)
      4.times { |i| changes.neutral("n#{i}", "neutral #{i}") }
      2.times { |i| changes.regression("r#{i}", "regression #{i}") }
      result = changes.to_result

      expect(result.changes.map(&:kind)).to eq(%i[regression regression neutral])
      expect(result.counts).to eq(regression: 2, improvement: 0, neutral: 4)
      expect(result).to be_truncated
    end

    it "bounds the changes a huge document can produce" do
      before = { "items" => Array.new(ExchangeDelta::MAX_CHANGES + 5) { |i| "v#{i}" } }
      after = { "items" => Array.new(ExchangeDelta::MAX_CHANGES + 5) { |i| "w#{i}" } }
      result = compare(before, after, format: "other")
      expect(result.changes.size).to eq(ExchangeDelta::MAX_CHANGES)
      expect(result.counts[:neutral]).to eq(ExchangeDelta::MAX_CHANGES + 5)
      expect(result).to be_truncated
    end

    it "rejects an unknown kind" do
      expect { ExchangeDelta::Changes.new.add(:worse, "k", "s") }.to raise_error(ArgumentError)
    end

    it "serializes for the API" do
      result = compare(doc, doc.merge("a" => 2), format: "other")
      json = result.as_json
      expect(json).to include(first_version: false, auto_acceptable: false, truncated: false,
                              counts: { regression: 0, improvement: 0, neutral: 1 })
      expect(json[:changes]).to eq([ { kind: "neutral", key: "/a", summary: "/a: 1 → 2", before: 1, after: 2 } ])
    end

    it "bounds a long text value a change carries" do
      result = compare(doc, doc.merge("a" => "x" * 2_000), format: "other")
      expect(result.changes.first.after.size).to eq(ExchangeDelta::MAX_VALUE_CHARS)
    end
  end

  describe "a document that cannot be compared" do
    it "reports one neutral change saying why, so the version waits for a person" do
      result = compare(JSON.generate(doc), "{not json", format: "fedramp", document_type: "vulnerability-detail-report")
      expect(result.changes.map(&:summary)).to contain_exactly(a_string_starting_with("Not compared: not valid JSON"))
      expect(result.counts).to eq(regression: 0, improvement: 0, neutral: 1)
      expect(result).not_to be_auto_acceptable
    end
  end

  describe "an unknown format (field-by-field, all neutral)" do
    it "reports added, removed and changed fields by JSON Pointer" do
      after = { "b" => { "c" => "y" }, "d" => [ 1 ] }
      result = compare(doc, after, format: "other")
      expect(result.changes.map(&:summary)).to contain_exactly(
        "/a: removed (was 1)", "/b/c: x → y", "/d: added ((1 item))"
      )
      expect(result.changes.map(&:kind).uniq).to eq([ :neutral ])
    end

    it "compares lists of identified entries by identifier, so reordering is no change" do
      before = { "list" => [ { "uuid" => "u1", "v" => 1 }, { "uuid" => "u2", "v" => 2 } ] }
      after = { "list" => [ { "uuid" => "u2", "v" => 2 }, { "uuid" => "u1", "v" => 3 } ] }
      expect(compare(before, after, format: "other").changes.map(&:summary)).to eq([ "/list/u1/v: 1 → 3" ])
    end

    it "escapes pointer segments (RFC 6901)" do
      result = compare({ "a/b" => 1, "c~d" => 1 }, { "a/b" => 2, "c~d" => 2 }, format: "other")
      expect(result.changes.map(&:key)).to eq(%w[/a~1b /c~0d])
    end

    it "compares XML byte-wise" do
      result = compare("<a>1</a>", "<a>2</a>", format: "other")
      expect(result.changes.map(&:summary)).to eq([ "Document changed (compared byte-wise)" ])
    end
  end
end
