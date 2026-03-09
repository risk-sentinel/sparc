require "rails_helper"

RSpec.describe OscalFormatDetectionService do
  describe ".detect" do
    context "extension-based detection" do
      it "detects .json extension" do
        result = described_class.detect(filename: "ssp-example.json")
        expect(result.format).to eq(:json)
        expect(result.detected_by).to eq(:extension)
      end

      it "detects .yaml extension" do
        result = described_class.detect(filename: "ssp-example.yaml")
        expect(result.format).to eq(:yaml)
        expect(result.detected_by).to eq(:extension)
      end

      it "detects .yml extension" do
        result = described_class.detect(filename: "ssp-example.yml")
        expect(result.format).to eq(:yaml)
        expect(result.detected_by).to eq(:extension)
      end

      it "detects .xml extension" do
        result = described_class.detect(filename: "ssp-example.xml")
        expect(result.format).to eq(:xml)
        expect(result.detected_by).to eq(:extension)
      end

      it "is case-insensitive for extensions" do
        result = described_class.detect(filename: "SSP.JSON")
        expect(result.format).to eq(:json)
      end

      it "works with file_path parameter" do
        result = described_class.detect(file_path: "/tmp/uploads/ssp.yaml")
        expect(result.format).to eq(:yaml)
        expect(result.detected_by).to eq(:extension)
      end
    end

    context "content-based detection" do
      it "detects JSON from content starting with {" do
        result = described_class.detect(content: '{"system-security-plan": {}}')
        expect(result.format).to eq(:json)
        expect(result.detected_by).to eq(:content)
      end

      it "detects JSON from content starting with [" do
        result = described_class.detect(content: '[{"id": 1}]')
        expect(result.format).to eq(:json)
        expect(result.detected_by).to eq(:content)
      end

      it "detects XML from content starting with <" do
        result = described_class.detect(content: '<?xml version="1.0"?><root/>')
        expect(result.format).to eq(:xml)
        expect(result.detected_by).to eq(:content)
      end

      it "detects YAML from content with document start marker" do
        result = described_class.detect(content: "---\nsystem-security-plan:\n  uuid: abc")
        expect(result.format).to eq(:yaml)
        expect(result.detected_by).to eq(:content)
      end

      it "detects YAML from content with key-value pairs" do
        result = described_class.detect(content: "system-security-plan:\n  uuid: abc")
        expect(result.format).to eq(:yaml)
        expect(result.detected_by).to eq(:content)
      end

      it "handles content with leading whitespace" do
        result = described_class.detect(content: "  \n  {\"key\": \"value\"}")
        expect(result.format).to eq(:json)
      end
    end

    context "precedence" do
      it "prefers extension over content" do
        result = described_class.detect(filename: "doc.yaml", content: '{"json": true}')
        expect(result.format).to eq(:yaml)
        expect(result.detected_by).to eq(:extension)
      end
    end

    context "error handling" do
      it "raises ArgumentError when no format can be determined" do
        expect { described_class.detect }.to raise_error(ArgumentError, /Unable to detect/)
      end

      it "raises ArgumentError for unrecognized extension with no content" do
        expect { described_class.detect(filename: "doc.txt") }.to raise_error(ArgumentError)
      end
    end
  end
end
