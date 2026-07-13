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

  describe "XCCDF STIG with NIST resolution" do
    let(:fixture_path) { Rails.root.join("spec/fixtures/files/components/test-stig-xccdf.xml").to_s }
    let(:document) { create(:cdef_document, file_type: "xccdf", status: "processing") }
    let(:service) { described_class.new(document, fixture_path) }

    it "parses XCCDF STIG and creates controls" do
      service.parse
      document.reload

      expect(document.cdef_controls.count).to eq(2)
    end

    it "resolves NIST control IDs via CCI fallback" do
      service.parse
      document.reload

      # CCI-000366 maps to a NIST control (cm-6 in cci_to_nist.json)
      control = document.cdef_controls.find_by(stig_id: "SV-257777r925318_rule")
      expect(control.control_id).not_to start_with("SV-")
      expect(control.control_id).to match(/\A[a-z]{2}-\d+/)
    end

    it "preserves original rule_id as stig_id" do
      service.parse
      document.reload

      control = document.cdef_controls.find_by(stig_id: "SV-257777r925318_rule")
      expect(control.stig_id).to eq("SV-257777r925318_rule")
      expect(control.rule_id).to eq("SV-257777r925318_rule")
    end

    it "derives control_family from resolved NIST ID" do
      service.parse
      document.reload

      control = document.cdef_controls.find_by(stig_id: "SV-257777r925318_rule")
      expect(control.control_family).to be_present
      expect(control.control_family).to match(/\A[A-Z]{2}\z/)
    end

    it "stores nist_controls field when resolution succeeds" do
      service.parse
      document.reload

      control = document.cdef_controls.find_by(stig_id: "SV-257777r925318_rule")
      nist_field = control.cdef_control_fields.find_by(field_name: "nist_controls")
      expect(nist_field).to be_present
      expect(nist_field.field_value).to match(/\A[a-z]{2}-\d+/)
    end

    it "uses Converter entries when available" do
      # Create a stig_to_nist Converter with a known mapping
      converter = Converter.create!(
        name: "Test STIG Converter",
        converter_type: "stig_to_nist",
        version: "1.0",
        status: "complete",
        source_framework: "DISA STIG XCCDF",
        target_framework: "NIST SP 800-53"
      )
      ConverterEntry.create!(
        converter: converter,
        source_id: "SV-257777",
        target_id: "cm-6",
        relationship: "subset"
      )

      service.parse
      document.reload

      control = document.cdef_controls.find_by(stig_id: "SV-257777r925318_rule")
      expect(control.control_id).to eq("cm-6")
    end

    it "sets cdef_type to disa_stig" do
      service.parse
      document.reload

      expect(document.cdef_type).to eq("disa_stig")
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

      expect { service.parse }.to raise_error(DocumentParseError, /Unrecognized XML format/)
    ensure
      tmp&.unlink
    end
  end
end
