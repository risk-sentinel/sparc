require "rails_helper"

RSpec.describe HdfRunner do
  describe "subprocess invocation contract" do
    let(:runner) { described_class.new(binary: "fake-hdf") }

    def stub_open3(stdout: "", stderr: "", success: true, exit_code: 0)
      status = instance_double(Process::Status, success?: success, exitstatus: exit_code)
      allow(Open3).to receive(:capture3).and_return([ stdout, stderr, status ])
    end

    describe "#convert" do
      it "calls hdf with --json and returns parsed output" do
        stub_open3(stdout: '{"version":1,"profiles":[]}')
        result = runner.convert("/tmp/scan.json", from: "trivy")
        expect(result).to eq("version" => 1, "profiles" => [])
        expect(Open3).to have_received(:capture3).with(
          "fake-hdf", "convert", "--max-size", "50",
          "--from", "trivy", "--json", "/tmp/scan.json"
        )
      end

      it "passes --to when destination format specified" do
        stub_open3(stdout: "{}")
        runner.convert("/tmp/scan.json", from: "hdf", to: "oscal-sar")
        expect(Open3).to have_received(:capture3) do |*args|
          expect(args).to include("--to", "oscal-sar")
        end
      end

      it "raises HdfRunner::Error with stderr on non-zero exit" do
        stub_open3(stdout: "", stderr: "validation failed at line 42", success: false, exit_code: 1)
        expect {
          runner.convert("/tmp/scan.json")
        }.to raise_error(HdfRunner::Error) do |err|
          expect(err.exit_code).to eq(1)
          expect(err.stderr).to include("line 42")
          expect(err.command).to include("fake-hdf convert")
        end
      end

      it "raises HdfRunner::Error when hdf returns non-JSON" do
        stub_open3(stdout: "not json", stderr: "", success: true)
        expect {
          runner.convert("/tmp/scan.json")
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

    describe "#validate" do
      it "shells with --type and --quiet, returns true on success" do
        stub_open3(stdout: "")
        expect(runner.validate("/tmp/scan.json", type: "results")).to be true
        expect(Open3).to have_received(:capture3).with(
          "fake-hdf", "validate", "--type", "results", "--quiet", "/tmp/scan.json"
        )
      end

      it "raises on non-zero exit" do
        stub_open3(stdout: "", stderr: "schema mismatch", success: false, exit_code: 1)
        expect { runner.validate("/tmp/scan.json") }.to raise_error(HdfRunner::Error, /schema mismatch/)
      end
    end

    describe "#info / #stats" do
      it "passes --json and parses the result" do
        stub_open3(stdout: '{"controls":{"passed":10}}')
        expect(runner.stats("/tmp/scan.json")).to eq("controls" => { "passed" => 10 })
        expect(Open3).to have_received(:capture3).with(
          "fake-hdf", "stats", "--json", "/tmp/scan.json"
        )
      end
    end

    describe "#amend_verify" do
      it "shells `amend verify <path>` and returns true" do
        stub_open3(stdout: "")
        expect(runner.amend_verify("/tmp/amendments.json")).to be true
        expect(Open3).to have_received(:capture3).with(
          "fake-hdf", "amend", "verify", "/tmp/amendments.json"
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
          results: "/tmp/scan.json",
          amendments: "/tmp/amendments.json"
        )
        expect(result.dig("profiles", 0, "controls", 0, "id")).to eq("AC-2")
        expect(Open3).to have_received(:capture3) do |*args|
          expect(args).to include("amend", "apply", "--results", "/tmp/scan.json")
          expect(args).to include("--amendments", "/tmp/amendments.json")
        end
      end
    end

    describe "#version" do
      it "memoizes the parsed JSON" do
        stub_open3(stdout: '{"version":"3.2.0"}')
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

    it "returns version metadata" do
      v = runner.version
      expect(v).to be_a(Hash)
      expect(v.values.join(" ")).to include(HdfRunner::PINNED_VERSION)
    end

    it "validates a known-good HDF results fixture" do
      fixture = File.expand_path("../../spec/fixtures/files/hdf/sample-results.hdf.json", __dir__)
      skip "fixture missing: #{fixture}" unless File.exist?(fixture)
      expect(runner.validate(fixture, type: "results")).to be true
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
