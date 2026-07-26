# frozen_string_literal: true

require "rails_helper"

RSpec.describe FieldImportService do
  describe ".parse" do
    it "parses canonical JSON { controls: { id => {field=>val} } }" do
      json = { "controls" => { "AC-1" => { "status" => "Implemented" } } }.to_json
      payload = described_class.parse(content: json, format: "json")
      expect(payload[:controls]).to eq([ { control_id: "AC-1", fields: { "status" => "Implemented" } } ])
    end

    it "parses YAML" do
      yaml = "controls:\n  AC-1:\n    status: Implemented\n"
      payload = described_class.parse(content: yaml, format: "yaml")
      expect(payload[:controls].first[:control_id]).to eq("AC-1")
    end

    it "accepts a bare { id => {field=>val} } map" do
      json = { "AC-1" => { "notes" => "hi" } }.to_json
      expect(described_class.parse(content: json, format: "json")[:controls].first[:control_id]).to eq("AC-1")
    end

    it "rejects empty / invalid / unsupported / contentless input" do
      expect { described_class.parse(content: "", format: "json") }.to raise_error(described_class::ImportError, /Empty/)
      expect { described_class.parse(content: "{ bad", format: "json") }.to raise_error(described_class::ImportError, /Invalid JSON/)
      expect { described_class.parse(content: "{}", format: "csv") }.to raise_error(described_class::ImportError, /Unsupported/)
      expect { described_class.parse(content: "{}", format: "json") }.to raise_error(described_class::ImportError, /No control field updates/)
    end
  end

  describe "#preview (SSP)" do
    let(:document) { create(:ssp_document) }
    let!(:control) { create(:ssp_control, ssp_document: document, control_id: "AC-1") }

    def payload(fields)
      described_class.parse(content: { "controls" => { "AC-1" => fields } }.to_json, format: "json")
    end

    it "classifies change / unchanged / non_editable / invalid / unknown" do
      create(:ssp_control_field, ssp_control: control, field_name: "notes", field_value: "old")
      result = described_class.new(document).preview(
        described_class.parse(content: {
          "controls" => {
            "AC-1" => { "status" => "Implemented", "notes" => "old", "class" => "nope", "coverage_level" => "BOGUS" },
            "ZZ-9" => { "status" => "Implemented" }
          }
        }.to_json, format: "json")
      )
      by = result[:rows].group_by { |r| [ r.control_id, r.field_name ] }
      expect(by[[ "AC-1", "status" ]].first.status).to eq("change")
      expect(by[[ "AC-1", "notes" ]].first.status).to eq("unchanged")
      expect(by[[ "AC-1", "class" ]].first.status).to eq("non_editable")
      expect(by[[ "AC-1", "coverage_level" ]].first.status).to eq("invalid")
      expect(by[[ "ZZ-9", "status" ]].first.status).to eq("unknown")
    end

    it "does not write anything (non-destructive)" do
      expect { described_class.new(document).preview(payload("status" => "Implemented")) }
        .not_to change(SspControlField, :count)
    end
  end

  describe "#apply (SSP)" do
    let(:document) { create(:ssp_document) }
    let!(:control) { create(:ssp_control, ssp_document: document, control_id: "AC-1") }

    it "writes editable/allowed changes and skips unknown/non_editable/invalid" do
      result = described_class.new(document).apply(
        described_class.parse(content: {
          "controls" => {
            "AC-1" => { "status" => "Implemented", "class" => "nope", "coverage_level" => "BOGUS" },
            "ZZ-9" => { "status" => "Implemented" }
          }
        }.to_json, format: "json")
      )
      expect(result[:applied]).to eq(1) # only status
      expect(control.ssp_control_fields.find_by(field_name: "status").field_value).to eq("Implemented")
      expect(control.ssp_control_fields.find_by(field_name: "class")).to be_nil
      expect(control.ssp_control_fields.find_by(field_name: "coverage_level")).to be_nil
      expect(result[:stats]).to include(changes: 1, non_editable: 1, invalid: 1, unknown: 1)
    end
  end

  describe "allowed_values per type" do
    it "enforces CDEF implementation_status vocabulary" do
      doc = create(:cdef_document)
      create(:cdef_control, cdef_document: doc, control_id: "AC-1")
      result = described_class.new(doc).preview(
        described_class.parse(content: {
          "controls" => { "AC-1" => { "implementation_status" => "not-a-status" } }
        }.to_json, format: "json")
      )
      expect(result[:rows].first.status).to eq("invalid")
    end
  end

  it "refuses an unsupported document type" do
    expect { described_class.new(Object.new) }.to raise_error(described_class::ImportError, /not supported/)
  end
end
