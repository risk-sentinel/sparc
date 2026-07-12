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
  PINNED_VERSION = "3.2.0".freeze
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

  def initialize(binary: ENV.fetch("HDF_BIN", DEFAULT_BINARY))
    @binary = binary
  end

  # Convert scanner output (or OSCAL document) to HDF JSON.
  # @param input [String, IO] file path or IO-like
  # @param from  [String, nil] source format key (e.g. "trivy", "sarif", "oscal-poam"); nil = auto-detect
  # @param to    [String, nil] destination format; nil emits HDF
  # @param max_size_mb [Integer]
  # @return [Hash] parsed JSON
  def convert(input, from: nil, to: nil, max_size_mb: 50)
    ensure_allowed_version!
    input = inject_baselines_if_needed(input, to)
    flags = [ "--max-size", max_size_mb.to_s ]
    flags += [ "--from", from ] if from
    flags += [ "--to",   to   ] if to
    flags << JSON_FLAG
    invoke_json("convert", flags, input: input)
  end

  # Validate input against the v3.2.0 schema. Raises on mismatch.
  # @param type [String] "results" | "baseline" | "amendments" | etc.
  def validate(input, type: "results")
    invoke("validate", [ "--type", type, "--quiet" ], input: input)
    true
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

  # hdf-cli 3.2.0 made a top-level `baselines` field required for the
  # hdf→oscal-sar conversion; standard scanner HDF (InSpec exec-json, SARIF→hdf,
  # etc.) has no such field, so the converter 422s with "missing baselines
  # field" (upstream mitre/hdf-libs#104). When normalization is enabled, inject
  # an empty `baselines: []` so the conversion proceeds.
  #
  # Gated on the doc looking like HDF — i.e. having a top-level `profiles` array
  # (the defining HDF results structure). Without this gate we'd inject into ANY
  # JSON object, and hdf-cli 3.2.0 happily turns `{"anything","baselines":[]}`
  # into a degenerate SAR (exit 0) — silently converting non-HDF garbage that
  # should be rejected. Requiring `profiles` keeps the "garbage in → 422" contract
  # while still fixing real scanner HDF. Only touches oscal-sar, only when
  # baselines is missing, only for JSON input.
  def inject_baselines_if_needed(input, to)
    return input unless to == "oscal-sar"
    return input unless SparcConfig.hdf_normalize_baselines?

    raw = read_input_content(input)
    return input if raw.nil?

    doc = JSON.parse(raw)
    return input unless doc.is_a?(Hash) && doc.key?("profiles") && !doc.key?("baselines")

    doc["baselines"] = []
    StringIO.new(JSON.generate(doc))
  rescue JSON::ParserError
    input # not JSON (or unreadable) — let hdf-cli handle the original
  end

  # Read input content without consuming it for the caller. Strings are
  # treated as paths; IO/path-like are read and rewound.
  def read_input_content(input)
    case input
    when String
      File.exist?(input) ? File.read(input) : nil
    else
      if input.respond_to?(:read)
        content = input.read
        input.rewind if input.respond_to?(:rewind)
        content
      elsif input.respond_to?(:path)
        File.read(input.path)
      end
    end
  end

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
    stdout, stderr, status = Open3.capture3(*cmd)
    return stdout if status.success?

    raise Error.new(
      "hdf #{cmd[1]} failed (exit #{status.exitstatus}): #{stderr.to_s.strip}",
      command: cmd.join(" "),
      exit_code: status.exitstatus,
      stderr: stderr.to_s
    )
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
