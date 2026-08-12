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

  cdef_paths.each do |path|
    context File.basename(path) do
      let(:data) { JSON.parse(File.read(path)) }

      it "is valid OSCAL against the component-definition schema" do
        result = OscalSchemaValidationService.validate(:component_definition, data)

        expect(result).to be_valid,
          -> { "#{File.basename(path)} is not valid OSCAL:\n  #{result.errors.first(5).join("\n  ")}" }
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
