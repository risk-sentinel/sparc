# frozen_string_literal: true

require "rails_helper"

RSpec.describe CdefXccdfParserService do
  describe "OSCAL XML auto-detection" do
    let(:fixture_path) { Rails.root.join("spec/fixtures/files/components/example-component-definition.xml").to_s }
    let(:document) { create(:cdef_document, file_type: "xccdf", status: "processing") }
    let(:service) { described_class.new(document, fixture_path) }

    it "auto-detects OSCAL component-definition XML and creates controls" do
      service.parse
      document.reload

      expect(document.cdef_controls.count).to eq(3)
    end

    it "extracts correct control_ids from OSCAL XML" do
      service.parse
      document.reload

      control_ids = document.cdef_controls.pluck(:control_id).sort
      expect(control_ids).to eq(%w[sa-4.9 sc-8 sc-8.1])
    end

    it "sets document metadata from OSCAL XML" do
      service.parse
      document.reload

      expect(document.cdef_type).to eq("custom")
      expect(document.oscal_version).to eq("1.1.2")
      expect(document.description).to eq("MongoDB Component Definition Example")
    end

    it "preserves the OSCAL uuid from XML" do
      service.parse
      document.reload

      expect(document.uuid).to eq("a7ba800c-a432-44cd-9075-0862cd66da6b")
    end

    it "extracts description fields from implemented-requirements" do
      service.parse
      document.reload

      sc8 = document.cdef_controls.find_by(control_id: "sc-8")
      desc_field = sc8.cdef_control_fields.find_by(field_name: "description")
      expect(desc_field.field_value).to include("SC-8")
    end

    it "derives control_family from control_id prefix" do
      service.parse
      document.reload

      sc8 = document.cdef_controls.find_by(control_id: "sc-8")
      expect(sc8.control_family).to eq("SC")
    end
  end

  describe "simple OSCAL XML" do
    let(:fixture_path) { Rails.root.join("spec/fixtures/files/components/example-component.xml").to_s }
    let(:document) { create(:cdef_document, file_type: "xccdf", status: "processing") }
    let(:service) { described_class.new(document, fixture_path) }

    it "parses simple OSCAL XML and creates controls" do
      service.parse
      document.reload

      expect(document.cdef_controls.count).to eq(2)
    end

    it "sets description from metadata title" do
      service.parse
      document.reload

      expect(document.description).to eq("Test Component Definition")
    end
  end

  describe "unrecognized XML format" do
    it "raises a descriptive error" do
      xml_content = '<?xml version="1.0"?><unknown-root><child/></unknown-root>'
      tmp = Tempfile.new([ "bad_xml_", ".xml" ])
      tmp.write(xml_content)
      tmp.close

      document = create(:cdef_document, file_type: "xccdf", status: "processing")
      service = described_class.new(document, tmp.path)

      expect { service.parse }.to raise_error(RuntimeError, /Unrecognized XML format/)
    ensure
      tmp&.unlink
    end
  end
end
