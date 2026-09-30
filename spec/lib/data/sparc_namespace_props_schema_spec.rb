# frozen_string_literal: true

require "rails_helper"
require "digest"

# #1154 — the SPARC-namespace props schema is vendored verbatim from
# sparc-horizon, with its provenance in a sidecar. A hand edit, a partial
# re-vendor or a sidecar left behind all fail here, so SparcNamespacePropsRule
# can never be validating against something nobody recorded.
RSpec.describe "vendored SPARC-namespace props schema" do
  let(:dir) { Rails.root.join("lib/data/oscal_ns") }
  let(:file) { "sparc-namespace-props.v1.schema.json" }
  let(:provenance) { JSON.parse(dir.join("sparc-namespace-props.v1.schema.provenance.json").read) }
  let(:schema) { JSON.parse(dir.join(file).read) }

  # Pinned here as well as in the sidecar: re-vendoring must be a deliberate
  # two-place change, not a sidecar regenerated to match whatever is on disk.
  let(:pinned_sha256) { "9dbe0bb4a0edf58403cf9ba304c5b3699128960b6b91b251b8adf4120521ce12" }

  it "is byte-for-byte the pinned upstream file" do
    bytes = dir.join(file).binread

    expect(Digest::SHA256.hexdigest(bytes)).to eq(pinned_sha256)
    expect(provenance.dig("files", file, "sha256")).to eq(pinned_sha256)
    expect(bytes.bytesize).to eq(provenance.dig("files", file, "bytes"))
  end

  it "records where it came from and under what license" do
    expect(provenance).to include(
      "source_repository" => "https://github.com/risk-sentinel/sparc-horizon",
      "source_path" => "schemas/#{file}",
      "license" => "Apache-2.0"
    )
    expect(provenance["source_commit"]).to match(/\A\h{40}\z/)
    expect(provenance.dig("files", file, "source_url")).to include(provenance["source_commit"])
  end

  it "pins the namespace SPARC registered (#1155), which is what the rule filters on" do
    expect(schema.dig("properties", "ns", "const")).to eq(OscalNamespace.uri(:sparc))
    expect(SparcNamespaceProps::NS).to eq(OscalNamespace.uri(:sparc))
  end

  it "defines exactly the nine names SPARC emits" do
    expect(schema.dig("properties", "name", "enum")).to match_array(SparcNamespaceProps::NAMES)
  end

  # The Ruby copies of the schema's patterns drive model validation and import
  # mapping; if upstream changes a pattern, these must change with it.
  it "carries the same trigger and date patterns SPARC validates input with" do
    trigger = schema["allOf"].find { |r| r.dig("if", "properties", "name", "const") == "trigger" }
    expect(trigger.dig("then", "properties", "value", "pattern")).to eq(SparcNamespaceProps::TRIGGER_PATTERN.source.sub('\A', "^").sub('\z', "$"))
    expect(schema.dig("$defs", "date", "pattern")).to eq(SparcNamespaceProps::DATE_PATTERN.source.sub('\A', "^").sub('\z', "$"))
  end
end
