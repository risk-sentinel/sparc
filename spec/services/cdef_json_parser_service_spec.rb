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

    it "stores import_metadata with format (back-matter now promoted to first-class records)" do
      service.parse
      document.reload

      expect(document.import_metadata["format"]).to eq("oscal_cdef")
      # #498 slice 3 — back-matter no longer stashed; it's promoted to
      # first-class BackMatterResource rows. See "promotes OSCAL
      # back-matter" example below.
      expect(document.import_metadata).not_to have_key("back_matter")
    end

    it "promotes OSCAL back-matter resources to first-class BackMatterResource rows (#498 slice 3)" do
      expect { service.parse }.to change(BackMatterResource, :count).by_at_least(1)
      document.reload

      promoted = document.back_matter_resources.where(source: "imported")
      expect(promoted).to be_present
      first = promoted.first
      expect(first.uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
      expect(first.title).to be_present
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

    it "resolves NIST control IDs from tags.nist" do
      service.parse
      document.reload

      # SV-257777 has tags.nist: ["CM-6 b"] → normalized to "cm-6.b"
      control = document.cdef_controls.find_by(stig_id: "SV-257777")
      expect(control.control_id).to eq("cm-6.b")
    end

    it "preserves original SV-ID as stig_id" do
      service.parse
      document.reload

      control = document.cdef_controls.find_by(stig_id: "SV-257777")
      expect(control.stig_id).to eq("SV-257777")
    end

    it "derives control_family from NIST ID" do
      service.parse
      document.reload

      control = document.cdef_controls.find_by(stig_id: "SV-257777")
      expect(control.control_family).to eq("CM")
    end

    it "stores resolved nist_controls field" do
      service.parse
      document.reload

      control = document.cdef_controls.find_by(stig_id: "SV-257777")
      nist_field = control.cdef_control_fields.find_by(field_name: "nist_controls")
      expect(nist_field.field_value).to eq("cm-6.b")
    end

    it "maps impact to severity correctly" do
      service.parse
      document.reload

      high_control = document.cdef_controls.find_by(stig_id: "SV-257777")
      expect(high_control.severity).to eq("high")

      medium_control = document.cdef_controls.find_by(stig_id: "SV-257778")
      expect(medium_control.severity).to eq("medium")
    end

    it "extracts description fields" do
      service.parse
      document.reload

      control = document.cdef_controls.find_by(stig_id: "SV-257777")
      desc_field = control.cdef_control_fields.find_by(field_name: "description")
      expect(desc_field.field_value).to include("vendor")
    end
  end
end
