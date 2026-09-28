# frozen_string_literal: true

require "rails_helper"
require "digest"
require "json_schemer"

# #1115 / #1172 — the vendored FedRAMP consolidated rules are verbatim copies of
# upstream, and their provenance is recorded in a sidecar. These examples keep
# the three in agreement: a hand edit, a partial re-vendor, or a sidecar that
# was not updated all fail here rather than importing something unrecorded.
RSpec.describe "vendored FedRAMP consolidated rules" do
  let(:dir) { Rails.root.join("lib/data/fedramp") }
  let(:provenance) { JSON.parse(dir.join("fedramp-consolidated-rules.provenance.json").read) }
  let(:data) { JSON.parse(dir.join("fedramp-consolidated-rules.json").read) }
  let(:schema) { JSON.parse(dir.join("fedramp-consolidated-rules.schema.json").read) }

  %w[fedramp-consolidated-rules.json fedramp-consolidated-rules.schema.json].each do |file|
    it "#{file} is byte-for-byte what the sidecar records" do
      bytes = dir.join(file).binread

      expect(Digest::SHA256.hexdigest(bytes)).to eq(provenance.dig("files", file, "sha256"))
      expect(bytes.bytesize).to eq(provenance.dig("files", file, "bytes"))
    end
  end

  it "records the upstream version the data file declares" do
    expect(data.dig("info", "version")).to eq(provenance["upstream_version"])
  end

  it "validates against the vendored schema (JSON Schema 2020-12)" do
    expect(schema["$schema"]).to eq("https://json-schema.org/draft/2020-12/schema")
    expect(JSONSchemer.schema(schema).validate(data).first(3).map { |e| e["error"] }).to eq([])
  end

  it "carries the KSI section the importer reads" do
    expect(data["KSI"].keys).to include("IAM", "CED", "CMT")
    expect(data["KSI"].values.sum { |theme| theme.fetch("indicators").size }).to be > 40
  end
end
