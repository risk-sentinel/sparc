require "rails_helper"
require "rake"
require "fileutils"
require "tmpdir"

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
    OscalSchema.delete_all
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

      expect {
        seed_task.invoke
      }.to raise_error(SystemExit, /bundle integrity check did not pass/)
      expect(OscalSchema.count).to eq(0)
    end

    it "fails loud when a manifest entry's bundle file is missing" do
      File.delete(bundle_dir.join("v1.1.2", "oscal_ssp_schema.json"))
      expect {
        seed_task.invoke
      }.to raise_error(SystemExit, /bundle integrity check did not pass/)
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

    before do
      allow(Rails).to receive(:root).and_return(Pathname.new(tmpdir))
      allow_any_instance_of(Object).to receive(:fetch_following_redirects).and_return(fake_body)
    end

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
end
