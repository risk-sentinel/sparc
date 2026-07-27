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

  # Elements are emitted with `send`, which finds any REAL method of that name
  # before Nokogiri's method_missing — including private Kernel ones. OSCAL
  # catalogs nest <select> inside <param>, so this raised
  # "TypeError: wrong argument type Hash (expected Array)" (Kernel#select), and
  # XML export of EVERY control catalog failed. The models covered above happen
  # not to contain a colliding name, which is why it went unnoticed.
  #
  # Both fixtures are real OSCAL shapes: one that previously FAILED and one that
  # always PASSED. Keeping the passing case next to the failing one is what shows
  # the fix targets the collision instead of disabling the code path.
  describe "element names that collide with a Ruby method" do
    let(:plain_catalog) do
      {
        "catalog" => {
          "uuid" => "11111111-1111-4111-8111-111111111111",
          "metadata" => { "title" => "Plain Catalog", "oscal-version" => "1.1.2" },
          "controls" => [ { "id" => "ac-1", "title" => "Policy" } ]
        }
      }
    end

    let(:catalog_with_select) do
      {
        "catalog" => {
          "uuid" => "22222222-2222-4222-8222-222222222222",
          "metadata" => { "title" => "Catalog With Select", "oscal-version" => "1.1.2" },
          "params" => [
            { "id" => "ac-1_prm_1", "label" => "frequency",
              "select" => { "how-many" => "one-or-more",
                            "choice" => [ "monthly", "quarterly" ] } }
          ]
        }
      }
    end

    def convert(data)
      described_class.new(:catalog, data).convert
    end

    it "still converts the shape that always worked" do
      doc = Nokogiri::XML(convert(plain_catalog))
      expect(doc.errors).to be_empty
      expect(doc.dup.remove_namespaces!.at_xpath("//metadata/title").text).to eq("Plain Catalog")
    end

    it "does not raise on the shape that used to fail" do
      expect { convert(catalog_with_select) }.not_to raise_error
    end

    it "emits a real <select> element rather than invoking Kernel#select" do
      doc = Nokogiri::XML(convert(catalog_with_select))
      expect(doc.errors).to be_empty

      sel = doc.dup.remove_namespaces!.at_xpath("//param/select")
      expect(sel).to be_present
      expect(sel["how-many"]).to eq("one-or-more")
      expect(sel.xpath("choice").map(&:text)).to eq(%w[monthly quarterly])
    end

    it "does not leak the disambiguating underscore into the output" do
      expect(convert(catalog_with_select)).not_to include("select_")
    end

    it "derives the collision list from the builder so it cannot drift" do
      expect(described_class::COLLIDING_ELEMENT_NAMES).to include("select", "class")
      Nokogiri::XML::Builder.instance_methods.each do |m|
        expect(described_class::COLLIDING_ELEMENT_NAMES).to include(m.to_s)
      end
    end
  end
end
