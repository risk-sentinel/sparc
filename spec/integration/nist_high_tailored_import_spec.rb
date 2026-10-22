# frozen_string_literal: true

require "rails_helper"

# NIST's Rev 5 HIGH baseline with every organization-defined parameter set,
# imported as a consumer would import their profile.
#
# Testers measured profile import dropping 615 of 690 ODPs on a HIGH profile:
# a parameter was kept only when its id started with the control id plus "_",
# and Rev 5 ids are zero-padded (`ac-01_odp.01` under `ac-1`). Every one of
# the fixture's parameters has to arrive.
RSpec.describe "NIST Rev 5 HIGH, tailored profile import" do
  let(:fixtures) { Rails.root.join("spec/fixtures/files") }
  let(:path) { fixtures.join("profiles/NIST_SP-800-53_rev5_HIGH-tailored_profile.json") }
  let(:tailored) { JSON.parse(File.read(path)) }
  let(:set_parameters) { tailored.dig("profile", "modify", "set-parameters").to_h { |p| [ p["param-id"], p["values"].join(", ") ] } }

  before do
    %w[NIST_SP-800-53_rev5_catalog.json NIST_SP-800-53_rev4_catalog.json].each do |name|
      CatalogImportService.call(File.open(fixtures.join("catalogs", name)), name)
    end
  end

  it "uses a fixture the OSCAL 1.2.3 profile schema accepts" do
    expect(OscalSchemaValidationService.validate(:profile, tailored, version: "1.2.3").errors).to be_empty
  end

  it "stores every parameter the profile sets, against the right control" do
    doc = create(:profile_document, status: "processing", file_type: "json", original_filename: File.basename(path))
    ProfileJsonParserService.new(doc, path.to_s).parse

    stored = ProfileControlField.joins(:profile_control)
                                .where(profile_controls: { profile_document_id: doc.id })
                                .where("field_name LIKE 'parameter:%'")
                                .pluck(:field_name, :field_value, "profile_controls.control_id")
    by_id = stored.to_h { |name, value, _| [ name.delete_prefix("parameter:"), value ] }

    missing = set_parameters.reject { |id, value| by_id[id] == value }
    expect(missing.keys).to be_empty, "#{missing.size} of #{set_parameters.size} not stored, e.g. #{missing.keys.first(5)}"

    misplaced = stored.reject { |name, _, control_id| ProfileParameterOwner.new(nil).belongs_to?(name.delete_prefix("parameter:"), control_id) }
    expect(misplaced).to be_empty
  end
end
