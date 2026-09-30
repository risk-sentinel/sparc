# frozen_string_literal: true

require "rails_helper"
require "digest"

# #1179 — the vendored hdf-system schema is a verbatim copy of the bundled
# schema the hdf-libs v3.7.0 CLI embeds, and its provenance is recorded in a
# sidecar. These keep the three in agreement, and prove the in-process
# validator built on it REFUSES what it must: a validator that passes
# everything looks exactly like one that works until something invalid ships.
RSpec.describe Hdf::SystemSchema do
  let(:dir) { Rails.root.join("lib/data/hdf") }
  let(:file) { "hdf-system.v#{described_class::VERSION}.schema.json" }
  let(:provenance) { JSON.parse(dir.join("hdf-system.v#{described_class::VERSION}.provenance.json").read) }
  let(:schema) { JSON.parse(dir.join(file).read) }

  describe "the vendored file" do
    it "is byte-for-byte what the sidecar records" do
      bytes = dir.join(file).binread

      expect(Digest::SHA256.hexdigest(bytes)).to eq(provenance.dig("files", file, "sha256"))
      expect(bytes.bytesize).to eq(provenance.dig("files", file, "bytes"))
    end

    it "is the hdf-system schema of the pinned hdf-libs release" do
      expect(schema["$schema"]).to eq("https://json-schema.org/draft/2020-12/schema")
      expect(schema["$id"]).to eq("https://mitre.github.io/hdf-libs/schemas/hdf-system/v#{described_class::VERSION}")
      expect(provenance["schema_id"]).to eq(schema["$id"])
      expect(provenance["source_tag"]).to eq("v#{HdfRunner::PINNED_VERSION}")
      expect(described_class::VERSION).to eq(HdfRunner::PINNED_VERSION)
    end

    it "is self-contained (every primitive embedded), so validation needs no network" do
      embedded = schema.fetch("$defs").keys
      expect(embedded).to include(
        "https://mitre.github.io/hdf-libs/schemas/primitives/component/v#{described_class::VERSION}",
        "https://mitre.github.io/hdf-libs/schemas/primitives/system/v#{described_class::VERSION}",
        "https://mitre.github.io/hdf-libs/schemas/primitives/common/v#{described_class::VERSION}"
      )
    end
  end

  describe ".errors" do
    let(:valid) do
      {
        "name" => "Portal",
        "systemId" => "8f7e1c94-0d3a-4b21-9c1e-2f4a6b8d0e13",
        "identifierScheme" => "urn:ietf:rfc:4122",
        "authorizationStatus" => "authorized",
        "authorizationDate" => "2025-06-15T00:00:00Z",
        "categorizationLevel" => "moderate",
        "owner" => { "identifier" => "so@example.gov", "type" => "email" },
        "components" => [
          { "type" => "application", "name" => "Web", "componentId" => "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee" }
        ],
        "controlDesignations" => [
          { "controlId" => "AC-2", "designation" => "hybrid", "description" => "Shared with the IdP." }
        ],
        "generator" => { "name" => "sparc", "version" => "1.0.0" },
        "labels" => { "system_id" => "8f7e1c94-0d3a-4b21-9c1e-2f4a6b8d0e13" }
      }
    end

    it "accepts a conformant document" do
      expect(described_class.errors(valid)).to eq([])
      expect(described_class.valid?(valid)).to be true
    end

    # Each refusal names the field it refused, so a pass here cannot be a
    # different, unrelated error happening to make the list non-empty.
    {
      "an undefined top-level key" => [ ->(d) { d.merge("bogusTopLevel" => 1) }, "/bogusTopLevel" ],
      "zero components" => [ ->(d) { d.merge("components" => []) }, "/components" ],
      "a missing name" => [ ->(d) { d.except("name") }, "/" ],
      "an authorizationStatus outside the enum" => [ ->(d) { d.merge("authorizationStatus" => "active") }, "/authorizationStatus" ],
      "a categorizationLevel outside the enum" => [ ->(d) { d.merge("categorizationLevel" => "fips-199-moderate") }, "/categorizationLevel" ],
      "a component type outside the enum" => [
        ->(d) { d.merge("components" => [ d["components"].first.merge("type" => "policy") ]) }, "/components/0/type"
      ],
      "an owner identity type outside the vocabulary" => [
        ->(d) { d.merge("owner" => { "identifier" => "x", "type" => "organization" }) }, "/owner/type"
      ],
      "a designation outside the enum" => [
        ->(d) { d.merge("controlDesignations" => [ d["controlDesignations"].first.merge("designation" => "inherited") ]) },
        "/controlDesignations/0/designation"
      ],
      "a designation without a description" => [
        ->(d) { d.merge("controlDesignations" => [ d["controlDesignations"].first.except("description") ]) },
        "/controlDesignations/0"
      ],
      "a systemId that is not a uuid" => [ ->(d) { d.merge("systemId" => "not-a-uuid") }, "/systemId" ],
      "a date-only authorizationDate" => [ ->(d) { d.merge("authorizationDate" => "2025-06-15") }, "/authorizationDate" ],
      "an identifierScheme that is not a uri-reference" => [ ->(d) { d.merge("identifierScheme" => "not a uri") }, "/identifierScheme" ],
      "a generator without a version" => [ ->(d) { d.merge("generator" => { "name" => "sparc" }) }, "/generator" ]
    }.each do |what, (mutate, pointer)|
      it "rejects #{what}" do
        errors = described_class.errors(mutate.call(valid))

        expect(errors).not_to be_empty
        expect(errors).to include(a_string_starting_with("#{pointer}:")),
          "expected an error at #{pointer}, got: #{errors.inspect}"
      end
    end
  end
end
