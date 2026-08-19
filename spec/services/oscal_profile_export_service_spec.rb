# frozen_string_literal: true

require "rails_helper"

# #433 slice 6 — OSCAL schema validation for Profile exports. The service's
# `#export` calls `OscalSchemaValidationService.validate!` internally and
# raises `OscalValidationError` on schema failure. Passing here proves the
# generated JSON conforms to NIST OSCAL profile v1.1.2.
RSpec.describe OscalProfileExportService do
  let(:catalog) { create(:control_catalog, name: "Reference Catalog") }
  let(:profile) do
    create(:profile_document,
           name: "Test Baseline Profile",
           baseline_level: "MODERATE",
           profile_version: "1.0.0",
           oscal_version: "1.1.2",
           control_catalog: catalog)
  end

  before do
    # The OSCAL profile schema requires at least one import; the export
    # service derives imports from profile_controls. A minimum-viable
    # profile needs at least one control.
    create(:profile_control,
           profile_document: profile,
           control_id: "ac-1",
           priority: "P1")
    create(:profile_control,
           profile_document: profile,
           control_id: "ac-2",
           priority: "P2")

    # #911 layer 2 — export refuses a control-id that resolves to no loaded
    # catalog. A profile selects FROM its catalog, so a profile control naming
    # something that catalog does not contain was never coherent; it only went
    # unnoticed because nothing checked.
    family = create(:control_family, control_catalog: catalog)
    create(:catalog_control, control_family: family, control_id: "ac-1")
    create(:catalog_control, control_family: family, control_id: "ac-2")
  end

  subject { described_class.new(profile) }

  # #989 — the shared contract.
  it_behaves_like "an OSCAL export with validated and unvalidated paths",
                  model_type: :profile,
                  service: -> { described_class.new(profile) }

  describe "#export — schema compliance" do
    it "produces schema-valid OSCAL JSON (validate! does not raise)" do
      expect { subject.export }.not_to raise_error
    end

    it "wraps the document under the `profile` root key" do
      data = JSON.parse(subject.export)
      expect(data).to have_key("profile")
    end

    it "preserves the profile uuid in the OSCAL output" do
      data = JSON.parse(subject.export)
      expect(data.dig("profile", "uuid")).to eq(profile.uuid)
    end

    it "carries the profile name into metadata.title" do
      data = JSON.parse(subject.export)
      expect(data.dig("profile", "metadata", "title")).to eq(profile.name)
    end

    it "uses the document's oscal_version when set" do
      data = JSON.parse(subject.export)
      expect(data.dig("profile", "metadata", "oscal-version")).to eq("1.1.2")
    end

    it "emits an imports[] array referencing the source catalog" do
      data = JSON.parse(subject.export)
      imports = data.dig("profile", "imports")
      expect(imports).to be_an(Array)
      expect(imports).not_to be_empty
    end
  end

  # ProfileControlSelectionService creates a `parameter:<id>` field for EVERY ODP
  # a control exposes, using the catalog param's label as the value — blank
  # whenever that param carries no label. The exporter emitted one set-parameter
  # per field, so a blank one produced "values": [], which OSCAL rejects
  # (minItems 1). That failed the WHOLE profile: any profile containing such a
  # control could not be exported in any format.
  #
  # Both cases are asserted together: a TAILORED parameter must still be emitted,
  # and an UNTAILORED one must be omitted rather than asserted as empty.
  describe "set-parameters for untailored ODPs" do
    let(:control) do
      profile.profile_controls.first ||
        create(:profile_control, profile_document: profile, control_id: "ac-1")
    end

    def set_parameters
      JSON.parse(subject.export_unvalidated).dig("profile", "modify", "set-parameters") || []
    end

    it "emits a parameter the author actually tailored" do
      create(:profile_control_field, profile_control: control,
             field_name: "parameter:ac-1_odp.01", field_value: "quarterly")

      entry = set_parameters.find { |p| p["param-id"] == "ac-1_odp.01" }
      expect(entry).to be_present
      expect(entry["values"]).to eq([ "quarterly" ])
    end

    it "omits an untailored parameter instead of emitting empty values" do
      create(:profile_control_field, profile_control: control,
             field_name: "parameter:ac-1_odp.02", field_value: "")

      expect(set_parameters.map { |p| p["param-id"] }).not_to include("ac-1_odp.02")
      expect(set_parameters).to all(satisfy { |p| p["values"].present? })
    end

    it "still validates against the OSCAL schema when an ODP is untailored" do
      create(:profile_control_field, profile_control: control,
             field_name: "parameter:ac-1_odp.01", field_value: "quarterly")
      create(:profile_control_field, profile_control: control,
             field_name: "parameter:ac-1_odp.02", field_value: "")

      expect { subject.export }.not_to raise_error
    end
  end
end
