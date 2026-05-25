# frozen_string_literal: true

require "rails_helper"

# #433 slice 6 — OSCAL schema validation for SSP exports. The service's
# `#export` calls `OscalSchemaValidationService.validate!` internally and
# raises `OscalValidationError` on schema failure. Passing here proves the
# generated JSON conforms to NIST OSCAL system-security-plan v1.1.2.
#
# Companion to `spec/services/oscal_ssp_export_inheritance_spec.rb`, which
# focuses on the inheritance / responsibility export edges. This spec
# covers the schema-validation surface.
RSpec.describe OscalSspExportService do
  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) do
    create(:ssp_document, :enriched,
           name: "Test System SSP",
           ssp_version: "1.0.0",
           oscal_version: "1.1.2",
           authorization_boundary: boundary)
  end

  before do
    # OSCAL SSP schema requires at minimum:
    #   - 1+ component (`this-system` always emitted by the service, but
    #     additional concrete components needed for downstream linkages)
    #   - 1+ user
    #   - 1+ information-type
    # Build a minimum-viable enriched SSP that satisfies each.
    create(:ssp_component,
           ssp_document: ssp,
           component_type: "software",
           title: "Application Server",
           description: "Test app server")
    create(:ssp_user,
           ssp_document: ssp,
           title: "System Owner",
           role_ids_data: [ "system-owner" ])
    create(:ssp_information_type,
           ssp_document: ssp,
           title: "Test Information Type",
           description: "Sample categorization entry")
    # SSP schema requires `implemented-requirements` array size >= 1.
    # The export service derives these from ssp_controls.
    create(:ssp_control,
           ssp_document: ssp,
           control_id: "ac-1",
           title: "Access Control Policy and Procedures")
  end

  subject { described_class.new(ssp) }

  describe "#export — schema compliance" do
    it "produces schema-valid OSCAL JSON (validate! does not raise)" do
      expect { subject.export }.not_to raise_error
    end

    it "wraps the document under the `system-security-plan` root key" do
      data = JSON.parse(subject.export)
      expect(data).to have_key("system-security-plan")
    end

    it "preserves the SSP uuid in the OSCAL output" do
      data = JSON.parse(subject.export)
      expect(data.dig("system-security-plan", "uuid")).to eq(ssp.uuid)
    end

    it "carries the SSP name into metadata.title" do
      data = JSON.parse(subject.export)
      expect(data.dig("system-security-plan", "metadata", "title")).to eq(ssp.name)
    end

    it "uses the document's oscal_version when set" do
      data = JSON.parse(subject.export)
      expect(data.dig("system-security-plan", "metadata", "oscal-version")).to eq("1.1.2")
    end

    it "carries the ssp_version into metadata.version" do
      data = JSON.parse(subject.export)
      expect(data.dig("system-security-plan", "metadata", "version")).to eq("1.0.0")
    end
  end
end
