# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/logging/sparc_json_formatter")

# #785 — SPARC_STRUCTURED_LOGGING was documented from day one as producing JSON
# logs but was never implemented. These specs pin the contract that log
# aggregators and NIST AU-3 evidence depend on.
RSpec.describe Logging::SparcJsonFormatter do
  subject(:formatter) { described_class.new }

  let(:ts) { Time.utc(2026, 7, 23, 12, 34, 56.789) }

  def emit(severity = "INFO", msg = "hello", time: ts)
    JSON.parse(formatter.call(severity, time, nil, msg))
  end

  it "emits one valid JSON object terminated by a newline" do
    line = formatter.call("INFO", ts, nil, "hello")
    expect(line).to end_with("\n")
    expect { JSON.parse(line) }.not_to raise_error
    expect(line.count("\n")).to eq(1), "a log line must not be split across records"
  end

  it "records timestamp in UTC ISO8601 with milliseconds" do
    expect(emit["ts"]).to eq("2026-07-23T12:34:56.789Z")
  end

  it "records the severity" do
    expect(emit("WARN")["level"]).to eq("WARN")
  end

  # The point of the whole exercise: request_id must be a FIELD, so an
  # aggregator can filter on it. As a text prefix it is only greppable.
  it "exposes the request id as a queryable field, not a message prefix" do
    result = formatter.tagged("req-123") { emit("INFO", "served") }

    expect(result["request_id"]).to eq("req-123")
    expect(result["msg"]).to eq("served")
    expect(result["msg"]).not_to include("req-123")
  end

  it "keeps additional tags as a list alongside the request id" do
    result = formatter.tagged("req-123", "tenant-a") { emit }

    expect(result["request_id"]).to eq("req-123")
    expect(result["tags"]).to eq([ "tenant-a" ])
  end

  it "omits tag fields entirely when nothing is tagged" do
    expect(emit.keys).not_to include("request_id", "tags")
  end

  it "renders exceptions as class and message rather than an object dump" do
    expect(emit("ERROR", ArgumentError.new("bad input"))["msg"])
      .to eq("ArgumentError: bad input")
  end

  it "handles non-string messages without raising" do
    expect(emit("INFO", { a: 1 })["msg"]).to include("a")
    expect(emit("INFO", nil)["msg"]).to eq("")
  end

  it "escapes content that would otherwise break the JSON envelope" do
    result = emit("INFO", 'quote " brace } newline' + "\n" + "tab\t")

    expect(result["msg"]).to include('quote "')
    expect(result["msg"]).to include("brace }")
  end

  # A logger that raises takes the process with it. Serialisation failure must
  # degrade to a valid record, never an exception.
  it "never raises, even when the message cannot be serialised" do
    hostile = Object.new
    def hostile.inspect = raise("boom")

    line = nil
    expect { line = formatter.call("INFO", ts, nil, hostile) }.not_to raise_error
    expect { JSON.parse(line) }.not_to raise_error
    expect(JSON.parse(line)["level"]).to eq("ERROR")
  end
end
