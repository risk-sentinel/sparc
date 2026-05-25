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
  end

  subject { described_class.new(profile) }

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
end
