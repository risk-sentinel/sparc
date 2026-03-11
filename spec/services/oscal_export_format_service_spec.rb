require "rails_helper"

RSpec.describe OscalExportFormatService do
  let(:sample_json) do
    {
      "system-security-plan" => {
        "uuid" => "test-uuid",
        "metadata" => {
          "title" => "Test SSP",
          "oscal-version" => "1.1.2"
        }
      }
    }.to_json
  end

  describe ".to_yaml" do
    it "converts JSON to valid YAML" do
      yaml = described_class.to_yaml(sample_json)

      expect(yaml).to include("system-security-plan")
      expect(yaml).to include("test-uuid")

      parsed = YAML.safe_load(yaml)
      expect(parsed["system-security-plan"]["uuid"]).to eq("test-uuid")
    end

    it "preserves nested metadata" do
      yaml = described_class.to_yaml(sample_json)
      parsed = YAML.safe_load(yaml)

      expect(parsed["system-security-plan"]["metadata"]["title"]).to eq("Test SSP")
      expect(parsed["system-security-plan"]["metadata"]["oscal-version"]).to eq("1.1.2")
    end

    it "produces a string" do
      yaml = described_class.to_yaml(sample_json)
      expect(yaml).to be_a(String)
    end
  end

  describe ".to_xml" do
    it "converts JSON to valid XML with OSCAL namespace" do
      xml = described_class.to_xml(sample_json, :ssp)

      expect(xml).to include('xmlns="http://csrc.nist.gov/ns/oscal/1.0"')
      expect(xml).to include("system-security-plan")

      doc = Nokogiri::XML(xml)
      expect(doc.errors).to be_empty
    end

    it "includes the XML declaration" do
      xml = described_class.to_xml(sample_json, :ssp)
      expect(xml).to include('<?xml version="1.0" encoding="UTF-8"?>')
    end

    it "embeds the uuid as an attribute" do
      xml = described_class.to_xml(sample_json, :ssp)
      expect(xml).to include('uuid="test-uuid"')
    end
  end
end
