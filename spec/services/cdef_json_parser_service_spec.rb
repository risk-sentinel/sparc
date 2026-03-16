# frozen_string_literal: true

require "rails_helper"

RSpec.describe CdefJsonParserService do
  describe "OSCAL Component Definition JSON" do
    let(:fixture_path) { Rails.root.join("spec/fixtures/files/components/example-component-definition.json").to_s }
    let(:document) { create(:cdef_document, file_type: "json", status: "processing") }
    let(:service) { described_class.new(document, fixture_path) }

    it "parses the OSCAL JSON and creates controls" do
      service.parse
      document.reload

      expect(document.cdef_controls.count).to eq(3)
    end

    it "extracts correct control_ids" do
      service.parse
      document.reload

      control_ids = document.cdef_controls.pluck(:control_id).sort
      expect(control_ids).to eq(%w[sa-4.9 sc-8 sc-8.1])
    end

    it "sets document metadata from OSCAL metadata" do
      service.parse
      document.reload

      expect(document.cdef_type).to eq("custom")
      expect(document.oscal_version).to eq("1.1.2")
      expect(document.cdef_version).to eq("20231012")
      expect(document.description).to eq("MongoDB Component Definition Example")
    end

    it "preserves the OSCAL uuid" do
      service.parse
      document.reload

      expect(document.uuid).to eq("a7ba800c-a432-44cd-9075-0862cd66da6b")
    end

    it "stores import_metadata with format and back_matter" do
      service.parse
      document.reload

      expect(document.import_metadata["format"]).to eq("oscal_cdef")
      expect(document.import_metadata["back_matter"]).to be_present
    end

    it "extracts description fields from implemented-requirements" do
      service.parse
      document.reload

      sc8 = document.cdef_controls.find_by(control_id: "sc-8")
      desc_field = sc8.cdef_control_fields.find_by(field_name: "description")
      expect(desc_field.field_value).to include("SC-8")
    end

    it "extracts component title as a field" do
      service.parse
      document.reload

      sc8 = document.cdef_controls.find_by(control_id: "sc-8")
      component_field = sc8.cdef_control_fields.find_by(field_name: "component")
      expect(component_field.field_value).to eq("MongoDB")
    end

    it "derives control_family from control_id prefix" do
      service.parse
      document.reload

      sc8 = document.cdef_controls.find_by(control_id: "sc-8")
      expect(sc8.control_family).to eq("SC")

      sa49 = document.cdef_controls.find_by(control_id: "sa-4.9")
      expect(sa49.control_family).to eq("SA")
    end
  end

  describe "simple OSCAL Component Definition JSON" do
    let(:fixture_path) { Rails.root.join("spec/fixtures/files/components/example-component.json").to_s }
    let(:document) { create(:cdef_document, file_type: "json", status: "processing") }
    let(:service) { described_class.new(document, fixture_path) }

    it "parses the simple OSCAL JSON and creates controls" do
      service.parse
      document.reload

      expect(document.cdef_controls.count).to eq(2)
    end

    it "sets document description from metadata title" do
      service.parse
      document.reload

      expect(document.description).to eq("Test Component Definition")
    end
  end

  describe "InSpec profile JSON" do
    let(:fixture_path) { Rails.root.join("spec/fixtures/files/components/rhel9-profile.json").to_s }
    let(:document) { create(:cdef_document, file_type: "json", status: "processing") }
    let(:service) { described_class.new(document, fixture_path) }

    it "parses InSpec profile and creates controls" do
      service.parse
      document.reload

      expect(document.cdef_controls.count).to be > 0
    end

    it "maps impact to severity correctly" do
      service.parse
      document.reload

      high_control = document.cdef_controls.find_by(control_id: "SV-257777")
      expect(high_control.severity).to eq("high")

      medium_control = document.cdef_controls.find_by(control_id: "SV-257778")
      expect(medium_control.severity).to eq("medium")
    end

    it "extracts description fields" do
      service.parse
      document.reload

      control = document.cdef_controls.find_by(control_id: "SV-257777")
      desc_field = control.cdef_control_fields.find_by(field_name: "description")
      expect(desc_field.field_value).to include("vendor")
    end
  end
end
