# frozen_string_literal: true

require "rails_helper"

# The OSCAL component definitions in docs/compliance/oscal/cdefs are shipped
# compliance artifacts — an assessor consumes them, and sparc-iac reads them.
#
# The compliance workflow validates them with `json.load`, which proves only
# that the bytes are JSON. It does not prove they are OSCAL. On that basis
# `component-definition-session-mgmt.json` carried an implemented-requirement
# whose uuid had an illegal RFC-4122 variant nibble
# (`f8b1c4d6-5e27-4a09-cf70-…` — the variant must be 8, 9, a or b), so the file
# was schema-INVALID in main and nothing said so (#934).
#
# This runs the same validator the export pipeline uses, so a hand-edited
# artifact fails here rather than in a consumer's toolchain.
RSpec.describe "OSCAL component definitions", type: :model do
  cdef_paths = Dir[Rails.root.join("docs/compliance/oscal/cdefs/*.json")].sort

  it "ships at least the five expected component definitions" do
    expect(cdef_paths.size).to be >= 5
  end

  # Uniqueness has to hold across the whole set, not just within one file: a
  # consumer that ingests all five and keys on uuid cannot tell two
  # same-uuid requirements apart, whichever files they came from.
  it "gives every implemented requirement a uuid unique across all of them" do
    uuids = cdef_paths.flat_map do |path|
      JSON.parse(File.read(path)).dig("component-definition", "components").to_a.flat_map do |component|
        component["control-implementations"].to_a.flat_map do |implementation|
          implementation["implemented-requirements"].to_a.map { |r| r["uuid"] }
        end
      end
    end

    duplicates = uuids.tally.select { |_uuid, count| count > 1 }.keys

    expect(duplicates).to be_empty, -> { "uuid reused across component definitions: #{duplicates.join(', ')}" }
  end

  cdef_paths.each do |path|
    context File.basename(path) do
      let(:data) { JSON.parse(File.read(path)) }
      let(:declared_version) { data.dig("component-definition", "metadata", "oscal-version") }

      it "is valid OSCAL against the component-definition schema" do
        result = OscalSchemaValidationService.validate(:component_definition, data)

        expect(result).to be_valid,
          -> { "#{File.basename(path)} is not valid OSCAL:\n  #{result.errors.first(5).join("\n  ")}" }
      end

      # #1117 — the drift guard. All five files sat at 1.1.2 for three releases
      # after DEFAULT_VERSION moved to 1.2.2: SPARC exported at one version and
      # handed out evidence about ITSELF at another. Nothing failed, because
      # 1.1.2 is still a bundled schema — which is exactly why it went unnoticed
      # for three releases and got restated as fact in three documents.
      #
      # Equality, not ">=". A stamp AHEAD of DEFAULT_VERSION is the same defect
      # in the other direction: a conformance claim against a schema SPARC does
      # not ship and cannot validate against.
      it "declares the OSCAL version SPARC actually ships" do
        expect(declared_version).to eq(OscalSchema::DEFAULT_VERSION),
          -> { "#{File.basename(path)} declares oscal-version #{declared_version.inspect} while " \
               "OscalSchema::DEFAULT_VERSION is #{OscalSchema::DEFAULT_VERSION.inspect}. Re-emit the " \
               "artifact at the shipping version rather than relaxing this expectation." }
      end

      # Without this the stamp above is cosmetic — a string nothing reads.
      #
      # This reads the BUNDLED schema for the declared version off disk rather
      # than going through OscalSchemaValidationService with `version:`. The
      # service resolves versions out of the `oscal_schemas` TABLE, which the
      # test database never seeds, so every version request falls through to the
      # single unversioned file in lib/oscal_schemas — and the Result still
      # reports `schema_version` as whatever was ASKED for. Requesting "9.9.9"
      # comes back valid, at "9.9.9". An example built on that would pass for a
      # stamp naming a version that does not exist.
      #
      # (The unversioned fallback file is byte-identical to
      # lib/oscal_schemas_bundle/v1.2.2 today, which is why these artifacts
      # validated cleanly for three releases while stamped 1.1.2.)
      it "is valid against the bundled schema for the version it declares" do
        schema_path = Rails.root.join("lib/oscal_schemas_bundle/v#{declared_version}/oscal_component_schema.json")
        expect(schema_path).to exist,
          -> { "#{File.basename(path)} declares OSCAL #{declared_version}, which SPARC does not bundle a " \
               "schema for — the claim cannot be checked, let alone met." }

        schemer = JSONSchemer.schema(OscalSchema.preprocess_schema(JSON.parse(schema_path.read)))
        errors  = schemer.validate(data).first(5).map { |e| "#{e['data_pointer'].presence || '(root)'}: #{e['type']}" }

        expect(errors).to be_empty,
          -> { "#{File.basename(path)} claims OSCAL #{declared_version} and is not valid against the " \
               "bundled v#{declared_version} schema:\n  #{errors.join("\n  ")}" }
      end

      # A duplicate uuid is legal JSON and legal against the schema, but it
      # makes two requirements indistinguishable to a consumer that keys on it.
      it "gives every implemented requirement a distinct uuid" do
        uuids = data.dig("component-definition", "components").to_a.flat_map do |component|
          component["control-implementations"].to_a.flat_map do |implementation|
            implementation["implemented-requirements"].to_a.map { |r| r["uuid"] }
          end
        end

        expect(uuids).to eq(uuids.uniq)
      end
    end
  end
end
