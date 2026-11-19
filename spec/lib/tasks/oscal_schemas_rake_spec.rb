require "rails_helper"
require "rake"
require "fileutils"
require "tmpdir"
require "stringio"

# Specs for the bundle-and-seed flow added in #453. Avoid hitting NIST
# GitHub: WebMock-style stubbing isn't enabled here, so we use a
# temporary bundle directory + Rails.root override and verify the
# disk-side behavior (manifest layout, SHA-256 verification, three-tier
# fallback) without any network round-trip.
RSpec.describe "lib/tasks/oscal_schemas.rake", type: :task do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:bundle_task) { Rake::Task["oscal:bundle_schemas"] }
  let(:seed_task)   { Rake::Task["oscal:seed_schemas"] }

  before do
    bundle_task.reenable
    seed_task.reenable
    # Rake keeps a failed task's exception and raises it again on the next
    # invoke, so a refused fetch in one example would surface in the next.
    Rake::Task["oscal:bundle_xsd_schemas"].reenable
    OscalSchema.delete_all
  end

  # #747 — capture the task's own diagnostic output so the failure-path examples
  # (checksum mismatch, missing file, no-network) don't flood the test log with
  # alarming ✗/FAILED lines. Assert against `task_output` where the diagnostic
  # itself is the behavior under test.
  let(:task_output) { StringIO.new }
  around do |example|
    Thread.current[:oscal_task_io] = task_output
    example.run
  ensure
    Thread.current[:oscal_task_io] = nil
  end

  # #1380 — every path the bundle tasks fetch, as the pin file names them.
  def pinned_paths
    json = OscalSchema::SUPPORTED_VERSIONS.flat_map do |version|
      OscalSchema::DOCUMENT_TYPE_MAP.filter_map do |doc_type, config|
        next if doc_type == "mapping" && !OscalSchema::MAPPING_VERSIONS.include?(version)

        "v#{version}/#{config[:file]}"
      end
    end
    xsd = OscalSchema::XSD_VERSIONS.flat_map do |version|
      OscalSchemaValidationService::XSD_SCHEMA_MAP.values.map { |file| "v#{version}/#{file}" }
    end
    { "json" => json, "xsd" => xsd }
  end

  # Pins that accept exactly these bodies, so a stubbed fetch is the pinned file.
  def pins_accepting(json_body, xsd_body)
    paths = pinned_paths
    {
      "json" => paths["json"].index_with { Digest::SHA256.hexdigest(json_body) },
      "xsd" => paths["xsd"].index_with { Digest::SHA256.hexdigest(xsd_body) }
    }
  end

  def with_pins(pins)
    Thread.current[:oscal_schema_pins] = pins
    yield
  ensure
    Thread.current[:oscal_schema_pins] = nil
  end

  describe "lib/oscal_schema_pins.json (#1380)" do
    let(:pins) { JSON.parse(File.read(Rails.root.join("lib/oscal_schema_pins.json"))) }

    it "pins every schema the bundle tasks fetch, and nothing else" do
      expect(pins["json"].keys).to match_array(pinned_paths["json"])
      expect(pins["xsd"].keys).to match_array(pinned_paths["xsd"])
    end

    it "pins each one by a SHA-256" do
      expect(pins["json"].values + pins["xsd"].values).to all(match(/\A\h{64}\z/))
    end
  end

  describe "oscal:seed_schemas — bundle path" do
    let(:tmpdir) { Dir.mktmpdir("oscal-bundle-spec-") }
    after { FileUtils.rm_rf(tmpdir) }

    let(:bundle_dir)    { Pathname.new(tmpdir).join("lib", "oscal_schemas_bundle") }
    let(:manifest_path) { bundle_dir.join("manifest.json") }

    let(:fake_schema) do
      {
        "$id" => "http://localhost/test_schema",
        "type" => "object",
        "properties" => { "ssp" => { "type" => "object" } }
      }
    end

    before do
      FileUtils.mkdir_p(bundle_dir.join("v1.1.2"))
      schema_file = bundle_dir.join("v1.1.2", "oscal_ssp_schema.json")
      File.write(schema_file, JSON.generate(fake_schema))

      sha256 = Digest::SHA256.hexdigest(JSON.generate(fake_schema))
      manifest = {
        "generated_at"       => Time.now.utc.iso8601,
        "supported_versions" => [ "1.1.2" ],
        "default_version"    => "1.1.2",
        "schemas" => [ {
          "version"       => "1.1.2",
          "document_type" => "ssp",
          "file"          => "v1.1.2/oscal_ssp_schema.json",
          "root_key"      => "system-security-plan",
          "sha256"        => sha256,
          "source_url"    => "test://fake",
          "size"          => JSON.generate(fake_schema).bytesize
        } ]
      }
      File.write(manifest_path, JSON.pretty_generate(manifest))

      # Redirect Rails.root → tmp so the rake task picks up the test bundle
      allow(Rails).to receive(:root).and_return(Pathname.new(tmpdir))
    end

    it "loads schemas from the bundle without network access" do
      expect(Net::HTTP).not_to receive(:start)
      seed_task.invoke
      expect(OscalSchema.count).to eq(1)
      schema = OscalSchema.find_schema(document_type: "ssp", oscal_version: "1.1.2")
      expect(schema).to be_present
      expect(schema.source_url).to start_with("bundle://")
    end

    it "verifies SHA-256 from the manifest before loading" do
      schema_file = bundle_dir.join("v1.1.2", "oscal_ssp_schema.json")
      File.write(schema_file, '{"tampered":true}')

      expect { seed_task.invoke }.to raise_error(SystemExit)
      # The failure message now travels through the captured task IO (#747),
      # not the SystemExit itself, so nothing hits the console.
      expect(task_output.string).to match(/bundle integrity check did not pass/)
      expect(task_output.string).to match(/SHA-256 mismatch/)
      expect(OscalSchema.count).to eq(0)
    end

    it "fails loud when a manifest entry's bundle file is missing" do
      File.delete(bundle_dir.join("v1.1.2", "oscal_ssp_schema.json"))
      expect { seed_task.invoke }.to raise_error(SystemExit)
      expect(task_output.string).to match(/bundle file missing/)
      expect(task_output.string).to match(/bundle integrity check did not pass/)
    end
  end

  describe "oscal:seed_schemas — network fallback path" do
    let(:tmpdir)     { Dir.mktmpdir("oscal-no-bundle-spec-") }
    after { FileUtils.rm_rf(tmpdir) }

    before do
      # No oscal_schemas_bundle/ in the tmp Rails.root → forces network branch
      allow(Rails).to receive(:root).and_return(Pathname.new(tmpdir))
    end

    it "attempts the network path when no bundle is present" do
      # Stub the helper so we don't actually hit NIST GitHub
      allow_any_instance_of(Object).to receive(:fetch_following_redirects).and_raise("test stub: no network")
      # Only verify the bundle path isn't taken — network failures are
      # expected in this test mode.
      expect {
        seed_task.invoke
      }.not_to raise_error
    end
  end

  describe "oscal:bundle_schemas — manifest shape" do
    let(:tmpdir) { Dir.mktmpdir("oscal-bundle-write-spec-") }
    after { FileUtils.rm_rf(tmpdir) }

    let(:fake_body) { '{"$id":"http://localhost/x","type":"object"}' }

    # #1058 — `bundle_schemas` now invokes `bundle_xsd_schemas`, so the stub has
    # to serve BOTH kinds. Returning JSON for a `.xsd` URL made the XSD task
    # correctly reject it as not-XML, which is the task working — but it meant
    # this spec was exercising a failure path it never intended to.
    let(:fake_xsd) do
      %(<?xml version="1.0"?><xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" ) +
        %(version="#{OscalSchema::DEFAULT_VERSION}"><xs:element name="x"/></xs:schema>)
    end

    before do
      allow(Rails).to receive(:root).and_return(Pathname.new(tmpdir))
      allow_any_instance_of(Object).to receive(:fetch_following_redirects) do |_receiver, url|
        url.to_s.end_with?(".xsd") ? fake_xsd : fake_body
      end
    end

    around { |example| with_pins(pins_accepting(fake_body, fake_xsd)) { example.run } }

    it "writes manifest.json with one entry per (version × document_type)" do
      bundle_task.invoke
      manifest_path = Pathname.new(tmpdir).join("lib", "oscal_schemas_bundle", "manifest.json")
      expect(manifest_path).to exist
      manifest = JSON.parse(File.read(manifest_path))

      expect(manifest["supported_versions"]).to eq(OscalSchema::SUPPORTED_VERSIONS)
      expect(manifest["schemas"]).to all(include(
        "version", "document_type", "file", "root_key", "sha256", "source_url", "size"
      ))

      # Mapping schemas only exist in 1.2.0+ — manifest excludes earlier versions.
      mapping_versions = manifest["schemas"].select { |e| e["document_type"] == "mapping" }.map { |e| e["version"] }
      expect(mapping_versions).to match_array(OscalSchema::MAPPING_VERSIONS)
    end

    it "writes one schema file per manifest entry under v<version>/" do
      bundle_task.invoke
      manifest_path = Pathname.new(tmpdir).join("lib", "oscal_schemas_bundle", "manifest.json")
      manifest = JSON.parse(File.read(manifest_path))

      manifest["schemas"].each do |entry|
        path = Pathname.new(tmpdir).join("lib", "oscal_schemas_bundle", entry["file"])
        expect(path).to exist, "expected bundle file at #{path}"
      end
    end

    it "computes SHA-256 of each schema and stores it in the manifest" do
      bundle_task.invoke
      manifest = JSON.parse(File.read(Pathname.new(tmpdir).join("lib", "oscal_schemas_bundle", "manifest.json")))
      expect(manifest["schemas"]).to all(include("sha256" => Digest::SHA256.hexdigest(fake_body)))
    end
  end

  # #1380 — a download that is not the pinned file is refused, and not written.
  describe "pinned checksums" do
    let(:tmpdir) { Dir.mktmpdir("oscal-pins-spec-") }
    after { FileUtils.rm_rf(tmpdir) }

    let(:fake_body) { '{"$id":"http://localhost/x","type":"object"}' }
    let(:fake_xsd) do
      %(<?xml version="1.0"?><xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"><xs:element name="x"/></xs:schema>)
    end
    let(:xsd_task) { Rake::Task["oscal:bundle_xsd_schemas"] }

    before do
      allow(Rails).to receive(:root).and_return(Pathname.new(tmpdir))
      allow_any_instance_of(Object).to receive(:fetch_following_redirects) do |_receiver, url|
        url.to_s.end_with?(".xsd") ? fake_xsd : fake_body
      end
    end

    it "refuses a JSON schema whose SHA-256 differs from its pin, and does not write it" do
      pins = pins_accepting(fake_body, fake_xsd)
      pins["json"]["v1.2.3/oscal_ssp_schema.json"] = "0" * 64

      with_pins(pins) { expect { bundle_task.invoke }.to raise_error(SystemExit) }

      expect(task_output.string).to include("ssp v1.2.3: SHA-256 #{Digest::SHA256.hexdigest(fake_body)} " \
                                            "does not match the pinned #{'0' * 64}")
      expect(Pathname.new(tmpdir).join("lib/oscal_schemas_bundle/v1.2.3/oscal_ssp_schema.json")).not_to exist
      expect(Pathname.new(tmpdir).join("lib/oscal_schemas_bundle/v1.2.3/oscal_catalog_schema.json")).to exist
    end

    it "refuses an XSD whose SHA-256 differs from its pin, and does not write it" do
      pins = pins_accepting(fake_body, fake_xsd)
      pins["xsd"]["v1.2.3/oscal_poam_schema.xsd"] = "f" * 64

      with_pins(pins) do
        expect { xsd_task.invoke }.to raise_error(SparcHttp::Error, /poam v1\.2\.3: SHA-256 \h{64} does not match the pinned f{64}/)
      end
      expect(Pathname.new(tmpdir).join("lib/oscal_xsd_schemas/v1.2.3/oscal_poam_schema.xsd")).not_to exist
    end

    it "refuses a schema that has no pin at all" do
      pins = pins_accepting(fake_body, fake_xsd)
      pins["xsd"].delete("v1.1.2/oscal_ssp_schema.xsd")

      with_pins(pins) do
        expect { xsd_task.invoke }.to raise_error(SparcHttp::Error, %r{no pinned SHA-256 for v1\.1\.2/oscal_ssp_schema\.xsd})
      end
    end
  end
end
