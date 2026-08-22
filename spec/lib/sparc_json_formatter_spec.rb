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

  # ── Credential redaction (#834) ──────────────────────────────────────────
  #
  # Nothing logs a password on purpose. They arrive through paths nobody
  # intends: a driver failure reports the whole connection string, and
  # `inspect` on a resolved database config prints every value in it. Both land
  # in CloudWatch during an ECS deployment, where the password is then retained
  # for as long as the log group is. NIST AU-9 / IA-5(1).
  describe "credential redaction" do
    # A LOCAL, not a constant. A constant assigned in a `describe` block is not
    # scoped to it -- it lands on Object, where another spec file defining the
    # same name silently wins. That is #1035: these fixtures are interpolated
    # when the file loads, the assertion resolved `secret` when the example ran,
    # and by then it held a different file's value, so five redaction checks
    # searched the output for a string that had never been in the input. A local
    # is captured by each example's closure, so the two cannot diverge.
    #
    # It has to be a local rather than a `let`: the value is needed at load time
    # to build the table of examples below.
    secret = "Sup3r$ecret!"

    {
      "a connection URI"        => "could not connect: postgresql://app:#{secret}@db.rds:5432/prod",
      "libpq conninfo"          => "host=db.rds user=app password=#{secret} sslmode=require",
      "an inspected config"     => { adapter: "postgresql", password: secret }.inspect,
      "a JSON secret payload"   => %Q({"username":"app","password":"#{secret}"}),
      "a non-database URI"      => "redis://default:#{secret}@cache:6379/1"
    }.each do |label, line|
      it "redacts the secret in #{label}" do
        # Pins the fixture to the assertion. Without this, an input that no
        # longer carries the secret still "passes" the expectation below, which
        # is precisely how #1035 stayed green.
        expect(line).to include(secret),
          "the fixture does not contain the secret being searched for, so the next line asserts nothing"

        expect(emit("ERROR", line)["msg"]).not_to include(secret)
      end
    end

    it "redacts a password carried on an exception message" do
      error = StandardError.new("FATAL: postgresql://app:#{secret}@db.rds:5432/prod refused")

      expect(emit("ERROR", error)["msg"]).not_to include(secret)
    end

    # Redaction that also destroys the diagnostic context is its own problem —
    # an operator still has to be able to tell WHICH connection failed.
    it "keeps everything that is not the secret" do
      msg = emit("ERROR", "host=db.rds port=5432 user=app password=#{secret} sslmode=require")["msg"]

      expect(msg).to include("host=db.rds", "port=5432", "user=app", "sslmode=require")
      expect(msg).to include("[REDACTED]")
    end

    # The escape hatch: sometimes the credential IS what you are debugging, and
    # "[REDACTED]" answers nothing. Opt-in only, and an initializer warns at
    # boot that anything logged while it is on must be treated as compromised.
    it "can be disabled deliberately for credential troubleshooting" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SPARC_LOG_CREDENTIALS", "false").and_return("true")

      line = "postgresql://app:#{secret}@db.rds:5432/prod"

      expect(described_class.new.call("ERROR", ts, nil, line)).to include(secret)
    end

    it "redacts by default when the variable is unset" do
      expect(ENV.fetch("SPARC_LOG_CREDENTIALS", "false")).to eq("false"),
        "redaction must be the default — an opt-OUT would leak on every deployment that forgot it"
    end

    it "leaves an ordinary line untouched" do
      line = "Completed 200 OK in 56ms (Views: 35.3ms | ActiveRecord: 0.0ms)"

      expect(emit("INFO", line)["msg"]).to eq(line)
    end
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
