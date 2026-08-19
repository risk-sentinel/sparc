# frozen_string_literal: true

require "rails_helper"

# #433 slice 6 — OSCAL schema validation for CDEF exports. The service's
# `#export` calls `OscalSchemaValidationService.validate!` internally and
# raises `OscalValidationError` on schema failure. Passing here proves the
# generated JSON conforms to NIST OSCAL component-definition v1.1.2.
RSpec.describe OscalComponentDefinitionExportService do
  let(:cdef) do
    create(:cdef_document,
           name: "Test Component Definition",
           cdef_type: "custom",
           cdef_version: "1.0.0",
           oscal_version: "1.1.2")
  end

  before do
    # OSCAL component-definition schema requires at least one component;
    # the export service derives components from cdef_controls, so a
    # minimum-viable CDEF needs at least one control.
    create(:cdef_control,
           cdef_document: cdef,
           control_id: "ac-1",
           title: "Access Control Policy")
  end

  subject { described_class.new(cdef) }

  # #989 — the shared contract, so this service cannot lose validation or gain
  # it on the unvalidated path without a spec saying so.
  it_behaves_like "an OSCAL export with validated and unvalidated paths",
                  model_type: :component_definition,
                  service: -> { described_class.new(cdef) }

  describe "#export — schema compliance" do
    it "produces schema-valid OSCAL JSON (validate! does not raise)" do
      expect { subject.export }.not_to raise_error
    end

    it "wraps the document under the `component-definition` root key" do
      data = JSON.parse(subject.export)
      expect(data).to have_key("component-definition")
    end

    it "preserves the CDEF uuid in the OSCAL output" do
      data = JSON.parse(subject.export)
      expect(data.dig("component-definition", "uuid")).to eq(cdef.uuid)
    end

    it "carries the CDEF name into metadata.title" do
      data = JSON.parse(subject.export)
      expect(data.dig("component-definition", "metadata", "title")).to eq(cdef.name)
    end

    it "uses the document's oscal_version when set" do
      data = JSON.parse(subject.export)
      expect(data.dig("component-definition", "metadata", "oscal-version")).to eq("1.1.2")
    end
  end

  # #982 — `control-implementation/@source` names the catalog or profile whose
  # controls the component claims to implement. #911 declared
  # `profile_document` as exactly that hop, and the export ignored it: a CDEF
  # built entirely from a published profile exported a `sparc.local` placeholder
  # carrying its own primary key, so the document declined to name its own
  # control basis. Schema-valid and wrong, which is why no validator caught it.
  describe "control-implementation source (#982)" do
    def exported_source
      JSON.parse(described_class.new(cdef.reload).export)
          .dig("component-definition", "components", 0, "control-implementations", 0, "source")
    end

    let(:profile) { create(:profile_document, lifecycle_status: "published") }

    it "names the linked profile when the CDEF was sourced from one" do
      cdef.update!(profile_document: profile, control_implementation_source: nil)

      expect(exported_source).to eq("uuid:#{profile.uuid}")
    end

    it "no longer emits the fabricated sparc.local placeholder for a profile-sourced CDEF" do
      cdef.update!(profile_document: profile, control_implementation_source: nil)

      expect(exported_source).not_to include("sparc.local")
      expect(exported_source).not_to include(cdef.id.to_s)
    end

    # #944 exists so a human can name a source SPARC has no record of. A form
    # field that silently loses to a foreign key would be its own defect.
    it "lets an authored source win over the linked profile" do
      cdef.update!(profile_document: profile,
                   control_implementation_source: "https://example.gov/catalog.json")

      expect(exported_source).to eq("https://example.gov/catalog.json")
    end

    it "still falls back to determine_source when there is neither" do
      cdef.update!(profile_document: nil, control_implementation_source: nil,
                   cdef_type: "disa_stig")

      expect(exported_source).to eq("https://public.cyber.mil/stigs/")
    end

    it "keeps the export schema-valid when the source comes from the profile" do
      cdef.update!(profile_document: profile, control_implementation_source: nil)

      expect { described_class.new(cdef.reload).export }.not_to raise_error
    end
  end
end
