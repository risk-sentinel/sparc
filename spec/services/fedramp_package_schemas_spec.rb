# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# #1354 / #1384 — FedRAMP's package schemas are vendored byte for byte and
# pinned. A file that is not the pinned one, or a file with no pin, must stop
# SPARC from using any of them.
RSpec.describe FedrampPackageSchemas do
  let(:provenance) { JSON.parse(File.read(described_class::PROVENANCE)) }

  after { described_class.reset! }

  it "pins every vendored file, and every pin names a vendored file" do
    on_disk = Dir[described_class::DIR.join("*.json")].map { |p| File.basename(p) }.sort
    expect(provenance["files"].keys.sort).to eq(on_disk)
    expect(on_disk.size).to eq(11)
  end

  it "records the upstream commit each file came from" do
    expect(provenance["source_repository"]).to eq("https://github.com/FedRAMP/schemas")
    expect(provenance["source_commit"]).to match(/\A\h{40}\z/)
    provenance["files"].each do |file, pin|
      expect(pin["source_url"]).to eq("https://raw.githubusercontent.com/FedRAMP/schemas/#{provenance['source_commit']}/#{file}")
    end
  end

  it "loads each schema with its $id, version and pinned SHA-256" do
    described_class.all.each do |type, schema|
      pin = provenance.dig("files", schema.file)
      expect(schema.id).to eq("https://fedramp.gov/schemas/#{schema.file}")
      expect(schema.id).to eq(pin["id"])
      expect(schema.version).to eq(pin["schema_version"])
      expect(schema.sha256).to eq(pin["sha256"])
      expect(schema.file).to eq("fedramp-#{type}-schema-2026-06-24.json")
    end
  end

  it "lists the documents a package can hold, not the shared definitions" do
    expect(described_class.document_types).to include("certification-package-overview", "security-decision-record",
                                                      "ongoing-certification-report", "vulnerability-detail-report",
                                                      "accepted-vulnerability-info")
    expect(described_class.document_types).not_to include(described_class::COMMON)
  end

  it "compiles every schema with its cross-file references resolved locally" do
    described_class.document_types.each do |type|
      expect(described_class.schemer(type).valid_schema?).to be(true), type
    end
  end

  it "never fetches a reference that is not a vendored schema" do
    expect { described_class.ref_resolver.call(URI("https://example.com/other.json")) }
      .to raise_error(described_class::Error, /not one of the vendored schemas/)
  end

  it "finds a schema from the www. host FedRAMP publishes at, too" do
    uri = "https://www.fedramp.gov/schemas/fedramp-vulnerability-detail-report-schema-2026-06-24.json"
    expect(described_class.for_schema_uri(uri).document_type).to eq("vulnerability-detail-report")
  end

  context "when a vendored file is changed or unpinned" do
    before do
      @dir = Pathname(Dir.mktmpdir("fedramp-schemas-"))
      FileUtils.cp(Dir[described_class::DIR.join("*.json")], @dir)
      stub_const("#{described_class}::DIR", @dir)
      described_class.reset!
    end

    after { FileUtils.remove_entry(@dir) }

    it "refuses a file whose bytes are not the pinned ones" do
      file = @dir.join("fedramp-vulnerability-detail-report-schema-2026-06-24.json")
      File.write(file, File.read(file).sub("\"title\"", "\"title\" "))
      expect { described_class.all }.to raise_error(described_class::Error, /does not match the pinned/)
    end

    it "refuses a schema file that has no pin" do
      File.write(@dir.join("fedramp-new-thing-schema-2026-06-24.json"), "{}")
      expect { described_class.all }.to raise_error(described_class::Error, /no pin/)
    end
  end
end
