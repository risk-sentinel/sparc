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
end
