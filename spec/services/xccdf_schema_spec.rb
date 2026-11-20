# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# #1354 — the XCCDF 1.2 schema set is vendored byte for byte and pinned, and
# loads without the network even though NIST's files import from absolute URLs.
RSpec.describe XccdfSchema do
  let(:provenance) { JSON.parse(File.read(described_class::PROVENANCE)) }

  after { described_class.reset! }

  def xccdf(benchmark_id: "xccdf_org.example_benchmark_test", rule_id: "xccdf_org.example_rule_one")
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Benchmark xmlns="http://checklists.nist.gov/xccdf/1.2" id="#{benchmark_id}" resolved="1">
        <status>accepted</status>
        <version>1.0</version>
        <Rule id="#{rule_id}" selected="true"><title>One</title></Rule>
      </Benchmark>
    XML
  end

  it "pins every vendored file, and every pin names a vendored file" do
    on_disk = Dir[described_class::DIR.join("*.xsd")].map { |p| File.basename(p) }.sort
    expect(provenance["files"].keys.sort).to eq(on_disk)
    provenance["files"].each_key do |file|
      expect(Digest::SHA256.file(described_class::DIR.join(file)).hexdigest).to eq(provenance.dig("files", file, "sha256"))
    end
  end

  it "has a local copy for every schema the vendored files import" do
    imported = Dir[described_class::DIR.join("*.xsd")].flat_map do |f|
      Nokogiri::XML(File.read(f)).xpath("//xsd:import/@schemaLocation", described_class::XSD_NS).map(&:value)
    end
    expect(imported.uniq).to all(satisfy { |loc| provenance["imports"].key?(loc) })
    expect(provenance["imports"].values).to all(satisfy { |file| provenance["files"].key?(file) })
  end

  it "accepts a well-formed XCCDF 1.2 benchmark" do
    expect(described_class.validate(Nokogiri::XML(xccdf))).to eq([])
  end

  it "accepts real XCCDF results" do
    doc = Nokogiri::XML(Rails.root.join("spec/fixtures/files/hdf/scap-xccdf-results-source.xml").read)
    expect(described_class.validate(doc)).to eq([])
  end

  it "reports an id that breaks XCCDF 1.2's naming rule, with its line" do
    errors = described_class.validate(Nokogiri::XML(xccdf(rule_id: "V-254238")))
    expect(errors).to include(a_string_matching(/\Aline \d+: .*V-254238/))
  end

  it "refuses to load a file whose bytes are not the pinned ones" do
    Dir.mktmpdir("xccdf-") do |dir|
      FileUtils.cp(Dir[described_class::DIR.join("*.xsd")], dir)
      File.write(File.join(dir, "xml.xsd"), File.read(File.join(dir, "xml.xsd")) + "\n")
      stub_const("#{described_class}::DIR", Pathname(dir))
      described_class.reset!
      expect { described_class.schema }.to raise_error(described_class::Error, /xml\.xsd.*does not match the pinned/)
    end
  end
end
