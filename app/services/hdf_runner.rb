require "open3"
require "tempfile"
require "json"
require "stringio"

# Subprocess wrapper around the MITRE hdf-libs CLI
# (https://github.com/mitre/hdf-libs).
#
# Centralizes every shellout to the `hdf` binary so that flag handling,
# version pinning, error-shape, and tempfile lifecycle live in one place.
# Callers receive parsed Ruby hashes for JSON-emitting subcommands and
# raise structured `HdfRunner::Error` for non-zero exits.
#
# Inputs may be either:
#   - a file path (String) — passed positionally to the binary
#   - an IO / StringIO     — written to a tempfile and passed positionally
#
# In both cases the input is realized as a file path before invocation,
# avoiding subtleties of stdin piping for large or binary payloads.
#
# NIST 800-53 controls covered:
#   CA-7 Continuous Monitoring (translation engine for tenant findings)
#   SI-2 Flaw Remediation     (amendment apply/verify integrate with the gate)
#   SA-11 Developer Testing   (validate against schema before persistence)
class HdfRunner
  JSON_FLAG = "--json".freeze
  # 3.7.0 (2026-09-23) — the org pin, matching the Dockerfile and the CI
  # runners. 3.5.1 was the first version whose `hdf -> oscal-sar` satisfied the
  # OSCAL schema (mitre/hdf-libs#184); re-measured on 3.7.0, that still holds —
  # oscal-sar and hdf-amendments -> oscal-poam both validate against the
  # bundled schemas at v1.1.2 and v1.2.2.
  #
  # The move off 3.5.1 is not cosmetic. 3.5.1's `amend verify` does not
  # validate appliedBy.type at all — it passes a document carrying
  # "totally-bogus-not-a-type" — and its `validate` accepts a legacy HDF v2
  # document against v3 schemas. Both are false passes we were relying on.
  # 3.7.0 enforces the vocabulary and detects v2, which is what surfaced the
  # non-conformant amendments this pin ships alongside.
  #
  # 3.7.2 (2026-10-16, v1.17.1) — upstream's fixes to filter-value handling,
  # component selector guards and CSV effective impact. Its embedded
  # hdf-system schema is byte-identical to 3.7.0's and still carries the
  # v3.7.0 $id, so Hdf::SystemSchema::VERSION (the SCHEMA version) stays 3.7.0.
  #
  # 3.8.0 (2026-11-16, v1.17.9, #1368) — an impact of 0 no longer means
  # notApplicable, SARIF severities follow SARIF §3.27.10, `extensions` is
  # closed, and a riskAdjustment override may not carry a status. Its embedded
  # hdf-system schema changed and carries the v3.8.0 $id, re-vendored with it.
  PINNED_VERSION = "3.8.0".freeze
  DEFAULT_BINARY = "hdf".freeze

  class Error < StandardError
    attr_reader :command, :exit_code, :stderr

    def initialize(message, command:, exit_code:, stderr:)
      super(message)
      @command = command
      @exit_code = exit_code
      @stderr = stderr
    end
  end

  # @param timeout [Numeric, nil] seconds an invocation may run before it is
  #   killed and raises (#1354). nil keeps the historical behaviour (no limit)
  #   for callers that have not opted in.
  def initialize(binary: ENV.fetch("HDF_BIN", DEFAULT_BINARY), timeout: nil)
    @binary = binary
    @timeout = timeout
  end

  # Convert scanner output (or OSCAL document) to HDF JSON.
  # @param input [String, IO] file path or IO-like
  # @param from  [String, nil] source format key (e.g. "trivy", "sarif", "oscal-poam"); nil = auto-detect
  # @param to    [String, nil] destination format; nil emits HDF
  # @param max_size_mb [Integer]
  # @return [Hash] parsed JSON
  def convert(input, from: nil, to: nil, max_size_mb: 50)
    ensure_allowed_version!
    flags = [ "--max-size", max_size_mb.to_s ]
    flags += [ "--from", from ] if from
    flags += [ "--to",   to   ] if to
    flags << JSON_FLAG
    invoke_json("convert", flags, input: input)
  end

  # Validate input against the bundled hdf-cli schema. Raises on mismatch.
  #
  # The CLI is the proof a document conforms — not our own reading of it, and
  # not a schema copy of ours that can drift from the binary that will consume
  # the document downstream.
  #
  # NOTE: `hdf validate --type results` still requires a top-level `baselines`
  # field — re-verified on 3.5.1 and again on 3.7.0 — while the oscal-sar
  # converter does not. The validator and the converter still disagree
  # upstream. Don't reach for this as a pre-flight check on scanner HDF; it
  # will reject input that converts fine. (HdfIngestService, #1354, does
  # pre-flight with it — but asks for `schema_ver: 2` on a v2 document, and
  # reads only what validated.)
  #
  # SCHEMA VERSION. hdf validate defaults to the CURRENT (v3) schemas. A legacy
  # HDF v2 document — InSpec exec-json, which is what most scanners still emit
  # through saf — is not v3 and must declare `schema_ver: 2`.
  #
  # This argument exists because 3.7.0 is the first version that can tell the
  # difference. 3.5.1 validated `spec/fixtures/files/hdf/sample-results.hdf.json`
  # — a v2 document — against the v3 schemas and reported SUCCESS. That green
  # meant nothing. 3.7.0 detects the v2 shape, refuses, and names the flag, so
  # asking for the right schema is now both possible and required.
  #
  # @param type [String] "results" | "baseline" | "amendments" | etc.
  # @param schema_ver [Integer, String, nil] HDF schema major version; nil uses
  #   the CLI default (current).
  def validate(input, type: "results", schema_ver: nil)
    flags = [ "--type", type, "--quiet" ]
    flags += [ "--schema-ver", schema_ver.to_s ] unless schema_ver.nil?
    invoke("validate", flags, input: input)
    true
  end

  # #1354 — upgrade a legacy HDF v2 (InSpec exec-json) results document to the
  # current v3 shape: `hdf convert --from hdf@2 --to hdf@3`.
  #
  # The output goes to a tempfile (`-o`), not stdout, so its size is checked
  # before it is read: a converter output larger than max_output_bytes raises
  # rather than being parsed. hdf validates its own converter output before it
  # writes, so a zero exit is a schema-valid v3 document.
  #
  # NIST 800-53: SI-10 (input validation — bounded output, fixed argv).
  #
  # @param input [String, IO] file path or IO-like holding the v2 document
  # @param max_output_bytes [Integer] refuse a converted document larger than this
  # @return [Hash] the parsed v3 results document
  def convert_legacy_hdf(input, max_output_bytes:)
    ensure_allowed_version!
    with_input_path(input) do |path|
      Tempfile.create([ "hdf-v3-", ".json" ]) do |out|
        cmd = build_cmd("convert", [ "--from", "hdf@2", "--to", "hdf@3", path, "-o", out.path ])
        run(cmd)
        size = File.size(out.path)
        if size > max_output_bytes
          raise Error.new("hdf convert output is #{size} bytes, over the #{max_output_bytes}-byte limit",
                          command: cmd.join(" "), exit_code: 0, stderr: "")
        end
        begin
          JSON.parse(File.read(out.path))
        rescue JSON::ParserError => e
          raise Error.new("hdf convert returned non-JSON output: #{e.message}",
                          command: cmd.join(" "), exit_code: 0, stderr: "")
        end
      end
    end
  end

  # Display assessment metadata (generator tool, profile, target, timestamp).
  def info(input)
    invoke_json("info", [ JSON_FLAG ], input: input)
  end

  # Pass/fail/error/not-applicable counts.
  def stats(input)
    invoke_json("stats", [ JSON_FLAG ], input: input)
  end

  # Schema-validate an Amendments document. Raises on failure.
  def amend_verify(amendments)
    with_input_path(amendments) do |path|
      invoke("amend", [ "verify", path ])
    end
    true
  end

  # #1208 — `amend verify --json`, returned WHATEVER the exit code.
  #
  # `amend_verify` raises on any failure, which folds three different answers
  # into one: an amendment past its expiresAt, an amendment that is invalid, and
  # a broken chain. The JSON report keeps them apart (`expiredOverrides`,
  # `invalidOverrides` + `schemaErrors`, `chain.valid`), and hdf-cli writes it
  # to stdout on exit 1 as well. A report that is not JSON still raises: no
  # report is not a clean report.
  def amend_verify_report(amendments)
    with_input_path(amendments) do |path|
      cmd = build_cmd("amend", [ "verify", JSON_FLAG, path ])
      stdout, stderr, status = Open3.capture3(*cmd)
      begin
        JSON.parse(stdout)
      rescue JSON::ParserError
        raise Error.new("hdf amend verify produced no report (exit #{status.exitstatus}): #{stderr.to_s.strip}",
                        command: cmd.join(" "), exit_code: status.exitstatus, stderr: stderr.to_s)
      end
    end
  end

  # Apply amendments to an HDF results file. Returns the amended HDF as a Hash.
  def amend_apply(results:, amendments:)
    with_input_path(results) do |results_path|
      with_input_path(amendments) do |amendments_path|
        Tempfile.create([ "hdf-amended-", ".json" ]) do |out|
          invoke("amend", [
            "apply",
            "--results", results_path,
            "--amendments", amendments_path,
            "-o", out.path
          ])
          JSON.parse(File.read(out.path))
        end
      end
    end
  end

  # Binary version metadata; cached per instance.
  def version
    @version ||= invoke_json("version", [ JSON_FLAG ])
  end

  # Convenience for callers that want to assert the embedded binary
  # matches our pinned target. Logs a warning rather than raising —
  # tenant tooling may run against a forward-compatible newer build.
  def warn_if_unpinned!
    actual = version["version"] || version["Version"] || "unknown"
    return if actual == PINNED_VERSION

    Rails.logger.warn(
      "[HdfRunner] embedded hdf-cli version #{actual} does not match pinned #{PINNED_VERSION}"
    ) if defined?(Rails) && Rails.logger
  end

  private

  # Refuse to run translations on an uncertified hdf-cli build when the
  # operator has pinned an allowlist (SPARC_HDF_ALLOWED_VERSIONS). No-op when
  # the allowlist is empty (accept the baked HDF_LIBS_VERSION).
  def ensure_allowed_version!
    allowed = SparcConfig.hdf_allowed_versions
    return if allowed.empty?

    actual = version["version"] || version["Version"] || "unknown"
    return if allowed.include?(actual)

    raise Error.new(
      "hdf-cli version #{actual} is not in SPARC_HDF_ALLOWED_VERSIONS (#{allowed.join(', ')})",
      command: "#{@binary} version", exit_code: 0, stderr: ""
    )
  end

  def invoke_json(subcommand, args, input: nil)
    raw = invoke(subcommand, args, input: input)
    JSON.parse(raw)
  rescue JSON::ParserError => e
    raise Error.new(
      "hdf #{subcommand} returned non-JSON output: #{e.message}",
      command: build_cmd(subcommand, args).join(" "),
      exit_code: 0,
      stderr: raw.to_s
    )
  end

  def invoke(subcommand, args, input: nil)
    cmd = build_cmd(subcommand, args)

    if input.nil?
      run(cmd)
    else
      with_input_path(input) do |path|
        run(cmd + [ path ])
      end
    end
  end

  def run(cmd)
    stdout, stderr, status = @timeout ? capture_with_timeout(cmd) : Open3.capture3(*cmd)
    return stdout if status.success?

    raise Error.new(
      "hdf #{cmd[1]} failed (exit #{status.exitstatus}): #{stderr.to_s.strip}",
      command: cmd.join(" "),
      exit_code: status.exitstatus,
      stderr: stderr.to_s
    )
  end

  # #1354 — Open3.capture3 with a deadline. Same fixed argv and no shell. The
  # child runs in its own process group so that on expiry the whole group is
  # killed (nothing it started keeps the pipes open), reaped, and Error is
  # raised with exit_code nil.
  def capture_with_timeout(cmd)
    Open3.popen3(*cmd, pgroup: true) do |stdin, stdout, stderr, wait|
      stdin.close
      out_reader = Thread.new { stdout.read }
      err_reader = Thread.new { stderr.read }
      unless wait.join(@timeout)
        kill_process_group(wait.pid)
        wait.join
        [ out_reader, err_reader ].each { |t| t.join(1) || t.kill }
        raise Error.new("hdf #{cmd[1]} timed out after #{@timeout}s",
                        command: cmd.join(" "), exit_code: nil, stderr: "")
      end
      [ out_reader.value, err_reader.value, wait.value ]
    end
  end

  def kill_process_group(pid)
    Process.kill("KILL", -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil # the group exited between the deadline and the kill
  end

  def build_cmd(subcommand, args)
    [ @binary, subcommand, *args.compact ]
  end

  # Yield a file path the binary can read from.
  #
  # Strings are trusted as paths — the caller knows what they passed.
  # Tempfile / Pathname / anything responding to :path is unwrapped.
  # IO / StringIO is materialized to a tempfile that's cleaned up after.
  def with_input_path(input)
    case input
    when String
      yield input
    else
      if input.respond_to?(:path)
        yield input.path
      elsif input.respond_to?(:read)
        Tempfile.create([ "hdf-input-", ".json" ]) do |f|
          f.binmode
          f.write(input.read)
          f.flush
          yield f.path
        end
      else
        raise ArgumentError, "input must be a file path, IO, or path-like, got #{input.class}"
      end
    end
  end
end
