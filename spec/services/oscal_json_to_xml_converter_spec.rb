require "rails_helper"

RSpec.describe OscalJsonToXmlConverter do
  describe "#convert" do
    it "converts an SSP hash to valid XML" do
      data = {
        "system-security-plan" => {
          "uuid" => "abc-123",
          "metadata" => {
            "title" => "Test SSP",
            "oscal-version" => "1.1.2"
          }
        }
      }

      xml = described_class.new(:ssp, data).convert

      expect(xml).to include('<?xml version="1.0" encoding="UTF-8"?>')
      expect(xml).to include('xmlns="http://csrc.nist.gov/ns/oscal/1.0"')
      expect(xml).to include('uuid="abc-123"')

      doc = Nokogiri::XML(xml)
      expect(doc.errors).to be_empty
    end

    it "renders props as self-closing elements with attributes" do
      data = {
        "system-security-plan" => {
          "uuid" => "abc",
          "metadata" => {
            "title" => "Test",
            "props" => [
              { "name" => "marking", "value" => "CUI" }
            ]
          }
        }
      }

      xml = described_class.new(:ssp, data).convert

      expect(xml).to include('name="marking"')
      expect(xml).to include('value="CUI"')
    end

    it "handles arrays by repeating the singular element" do
      data = {
        "system-security-plan" => {
          "uuid" => "abc",
          "metadata" => {
            "title" => "Test",
            "roles" => [
              { "id" => "admin", "title" => "Administrator" },
              { "id" => "user", "title" => "User" }
            ]
          }
        }
      }

      xml = described_class.new(:ssp, data).convert
      doc = Nokogiri::XML(xml)
      ns = { "o" => "http://csrc.nist.gov/ns/oscal/1.0" }
      roles = doc.xpath("//o:role", ns)

      expect(roles.size).to eq(2)
    end

    it "converts a component-definition hash to valid XML" do
      data = {
        "component-definition" => {
          "uuid" => "cdef-001",
          "metadata" => {
            "title" => "Test CDEF",
            "oscal-version" => "1.1.2"
          }
        }
      }

      xml = described_class.new(:component_definition, data).convert

      expect(xml).to include("component-definition")
      expect(xml).to include('uuid="cdef-001"')
      doc = Nokogiri::XML(xml)
      expect(doc.errors).to be_empty
    end

    it "converts a POA&M hash to valid XML" do
      data = {
        "plan-of-action-and-milestones" => {
          "uuid" => "poam-001",
          "metadata" => {
            "title" => "Test POAM",
            "oscal-version" => "1.1.2"
          }
        }
      }

      xml = described_class.new(:poam, data).convert

      expect(xml).to include("plan-of-action-and-milestones")
      expect(xml).to include('uuid="poam-001"')
      doc = Nokogiri::XML(xml)
      expect(doc.errors).to be_empty
    end

    it "raises for unknown model type" do
      expect { described_class.new(:unknown, {}) }.to raise_error(ArgumentError)
    end

    it "raises for missing root key" do
      expect { described_class.new(:ssp, { "wrong" => {} }).convert }.to raise_error(ArgumentError)
    end
  end
end
