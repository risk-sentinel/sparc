require "rails_helper"

RSpec.describe HdfRunner do
  describe "subprocess invocation contract" do
    let(:runner) { described_class.new(binary: fake_binary) }

    # Shared literals extracted to avoid duplication (Sonar S1192).
    let(:fake_binary)     { "fake-hdf" }
    let(:scan_path)       { "/tmp/scan.json" }
    let(:amendments_path) { "/tmp/amendments.json" }
    let(:baselines_key)   { "baselines" }
    let(:results_type)    { "results" }
    let(:oscal_sar)    { "oscal-sar" }
    let(:version_json) { '{"version":"3.4.1"}' }

    def stub_open3(stdout: "", stderr: "", success: true, exit_code: 0)
      status = instance_double(Process::Status, success?: success, exitstatus: exit_code)
      allow(Open3).to receive(:capture3).and_return([ stdout, stderr, status ])
    end

    describe "#convert" do
      it "calls hdf with --json and returns parsed output" do
        stub_open3(stdout: '{"version":1,"profiles":[]}')
        result = runner.convert(scan_path, from: "trivy")
        expect(result).to eq("version" => 1, "profiles" => [])
        expect(Open3).to have_received(:capture3).with(
          fake_binary, "convert", "--max-size", "50",
          "--from", "trivy", "--json", scan_path
        )
      end

      it "passes --to when destination format specified" do
        stub_open3(stdout: "{}")
        runner.convert(scan_path, from: "hdf", to: oscal_sar)
        expect(Open3).to have_received(:capture3) do |*args|
          expect(args).to include("--to", oscal_sar)
        end
      end

      it "raises HdfRunner::Error with stderr on non-zero exit" do
        stub_open3(stdout: "", stderr: "validation failed at line 42", success: false, exit_code: 1)
        expect {
          runner.convert(scan_path)
        }.to raise_error(HdfRunner::Error) do |err|
          expect(err.exit_code).to eq(1)
          expect(err.stderr).to include("line 42")
          expect(err.command).to include("fake-hdf convert")
        end
      end

      it "raises HdfRunner::Error when hdf returns non-JSON" do
        stub_open3(stdout: "not json", stderr: "", success: true)
        expect {
          runner.convert(scan_path)
        }.to raise_error(HdfRunner::Error, /returned non-JSON/)
      end

      it "writes a tempfile when input is an IO" do
        stub_open3(stdout: "{}")
        runner.convert(StringIO.new('{"hello":"world"}'))
        expect(Open3).to have_received(:capture3) do |*args|
          path = args.last
          expect(path).to match(%r{/hdf-input-.*\.json})
        end
      end
    end

    # #648 added a `baselines: []` injection to work around hdf-cli 3.2.0
    # requiring that field for hdf->oscal-sar (mitre/hdf-libs#104). Fixed
    # upstream in 3.3.1 and removed in #764: from the 3.4.1 pin the injection
    # was the only thing letting non-HDF input through -- garbage converts at
    # exit 0 with the field injected, and is correctly rejected without it.
    # These specs pin the absence of mutation so it can't be reintroduced.
    describe "#convert input pass-through (#764)" do
      def capture_input_content(stdout: "{}")
        captured = nil
        status = instance_double(Process::Status, success?: true, exitstatus: 0)
        allow(Open3).to receive(:capture3) do |*args|
          captured = File.read(args.last)
          [ stdout, "", status ]
        end
        yield
        captured
      end

      it "does not add baselines for oscal-sar when the field is missing" do
        content = capture_input_content do
          runner.convert(StringIO.new('{"version":1,"profiles":[]}'), from: "hdf", to: oscal_sar)
        end
        expect(JSON.parse(content)).not_to have_key(baselines_key)
      end

      it "passes the document through byte-for-byte" do
        original = '{"version":1,"profiles":[],"statistics":{}}'
        content = capture_input_content do
          runner.convert(StringIO.new(original), from: "hdf", to: oscal_sar)
        end
        expect(content).to eq(original)
      end

      it "leaves an existing baselines field untouched" do
        content = capture_input_content do
          runner.convert(StringIO.new('{"profiles":[],"baselines":[{"x":1}]}'), from: "hdf", to: oscal_sar)
        end
        expect(JSON.parse(content)[baselines_key]).to eq([ { "x" => 1 } ])
      end
    end


    describe "#convert version allowlist (SPARC_HDF_ALLOWED_VERSIONS)" do
      it "refuses to run when the hdf-cli version is not allowlisted" do
        allow(SparcConfig).to receive(:hdf_allowed_versions).and_return([ "3.1.0" ])
        stub_open3(stdout: version_json)
        expect {
          runner.convert(scan_path, to: "hdf")
        }.to raise_error(HdfRunner::Error, /not in SPARC_HDF_ALLOWED_VERSIONS/)
      end

      it "runs when the version is allowlisted" do
        allow(SparcConfig).to receive(:hdf_allowed_versions).and_return([ "3.4.1" ])
        stub_open3(stdout: version_json)
        expect { runner.convert(scan_path, to: "hdf") }.not_to raise_error
      end

      it "is a no-op (no version probe) when the allowlist is empty" do
        allow(SparcConfig).to receive(:hdf_allowed_versions).and_return([])
        stub_open3(stdout: "{}")
        runner.convert(scan_path, to: "hdf")
        # Only the convert shell-out — no extra `version` probe.
        expect(Open3).to have_received(:capture3).once
      end
    end

    describe "#validate" do
      it "shells with --type and --quiet, returns true on success" do
        stub_open3(stdout: "")
        expect(runner.validate(scan_path, type: results_type)).to be true
        expect(Open3).to have_received(:capture3).with(
          fake_binary, "validate", "--type", results_type, "--quiet", scan_path
        )
      end

      it "raises on non-zero exit" do
        stub_open3(stdout: "", stderr: "schema mismatch", success: false, exit_code: 1)
        expect { runner.validate(scan_path) }.to raise_error(HdfRunner::Error, /schema mismatch/)
      end
    end

    describe "#info / #stats" do
      it "passes --json and parses the result" do
        stub_open3(stdout: '{"controls":{"passed":10}}')
        expect(runner.stats(scan_path)).to eq("controls" => { "passed" => 10 })
        expect(Open3).to have_received(:capture3).with(
          fake_binary, "stats", "--json", scan_path
        )
      end
    end

    describe "#amend_verify" do
      it "shells `amend verify <path>` and returns true" do
        stub_open3(stdout: "")
        expect(runner.amend_verify(amendments_path)).to be true
        expect(Open3).to have_received(:capture3).with(
          fake_binary, "amend", "verify", amendments_path
        )
      end
    end

    describe "#amend_apply" do
      it "writes amended output to a tempfile and returns the parsed JSON" do
        stub_open3(stdout: "")
        # The amended-output tempfile is created by the runner; intercept the
        # File.read on it and substitute amended JSON.
        amended_payload = '{"profiles":[{"controls":[{"id":"AC-2","status":"passed"}]}]}'
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(/hdf-amended-.*\.json/).and_return(amended_payload)

        result = runner.amend_apply(
          results: scan_path,
          amendments: amendments_path
        )
        expect(result.dig("profiles", 0, "controls", 0, "id")).to eq("AC-2")
        expect(Open3).to have_received(:capture3) do |*args|
          expect(args).to include("amend", "apply", "--results", scan_path)
          expect(args).to include("--amendments", amendments_path)
        end
      end
    end

    describe "#version" do
      it "memoizes the parsed JSON" do
        stub_open3(stdout: version_json)
        2.times { runner.version }
        expect(Open3).to have_received(:capture3).once
      end
    end
  end

  describe "with the real binary", :hdf_binary do
    let(:binary) { ENV.fetch("HDF_BIN", "hdf") }

    before do
      skip "real `hdf` binary not on PATH; set HDF_BIN to override" unless binary_available?
    end

    let(:runner) { described_class.new(binary: binary) }
    let(:hdf_results_fixture) do
      File.expand_path("../../spec/fixtures/files/hdf/sample-results.hdf.json", __dir__)
    end

    # Accept any allowlisted version when SPARC_HDF_ALLOWED_VERSIONS is set,
    # else require the pin. CI bakes HDF_LIBS_VERSION so it still asserts
    # exactly; a developer mid-upgrade gets an actionable message instead of a
    # bare mismatch. The previous exact-only assert failed confusingly whenever
    # a local binary drifted from the pin, which is how a stale local hdf got
    # mis-attributed to unrelated work (#764).
    it "reports an accepted version" do
      reported = runner.version["version"] || runner.version["Version"]
      allowed  = SparcConfig.hdf_allowed_versions.presence || [ HdfRunner::PINNED_VERSION ]

      expect(allowed).to include(reported),
        "local hdf reports #{reported.inspect}, expected one of #{allowed.inspect}. " \
        "Upgrade with `sudo bin/install-hdf.sh` (check `which hdf` — a `go install` " \
        "build in $GOBIN can shadow it), or set SPARC_HDF_ALLOWED_VERSIONS=#{reported}."
    end

    it "validates a known-good HDF results fixture" do
      expect(runner.validate(hdf_results_fixture, type: "results")).to be true
    end

    # Pins an upstream divergence that is easy to trip over: as of 3.4.1 the
    # oscal-sar converter no longer requires a top-level `baselines` field
    # (fixed in 3.3.1, mitre/hdf-libs#104) but `validate --type results` still
    # does. So real scanner HDF converts fine yet fails validation — meaning
    # `validate` must NOT be used as a pre-flight check on the translation
    # path. If upstream ever reconciles the two, this spec fails and tells us.
    it "converts baseline-less scanner HDF that `validate` still rejects" do
      baseline_less = File.expand_path(
        "../../tests/api/fixtures/sample.hdf.json", __dir__
      )
      skip "fixture missing: #{baseline_less}" unless File.exist?(baseline_less)
      expect(JSON.parse(File.read(baseline_less))).not_to have_key("baselines")

      expect { runner.convert(baseline_less, from: "hdf", to: "oscal-sar") }.not_to raise_error
      expect { runner.validate(baseline_less, type: "results") }
        .to raise_error(HdfRunner::Error)
    end

    private

    def binary_available?
      _, _, status = Open3.capture3(binary, "version")
      status.success?
    rescue Errno::ENOENT
      false
    end
  end
end
