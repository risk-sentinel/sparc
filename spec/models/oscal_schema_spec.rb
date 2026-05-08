require "rails_helper"

RSpec.describe OscalSchema, type: :model do
  subject(:schema) do
    described_class.new(
      oscal_version: "1.1.2",
      document_type: "ssp",
      schema_format: "json",
      raw_schema: sample_schema,
      root_key: "system-security-plan",
      source_url: "https://example.com/schema.json",
      checksum: Digest::SHA256.hexdigest(sample_schema.to_json)
    )
  end

  let(:sample_schema) do
    {
      "$schema" => "http://json-schema.org/draft-07/schema#",
      "$id" => "http://csrc.nist.gov/ns/oscal/1.1.2/oscal_ssp_schema.json",
      "type" => "object",
      "definitions" => {
        "assembly_oscal-ssp_system-security-plan" => {
          "$id" => "#assembly_oscal-ssp_system-security-plan",
          "type" => "object",
          "properties" => {
            "uuid" => { "type" => "string" }
          }
        },
        "field_oscal-metadata_version" => {
          "$id" => "#field_oscal-metadata_version",
          "type" => "string"
        }
      },
      "properties" => {
        "system-security-plan" => {
          "$ref" => "#assembly_oscal-ssp_system-security-plan"
        }
      }
    }
  end

  describe "validations" do
    it { is_expected.to be_valid }

    it "requires oscal_version" do
      schema.oscal_version = nil
      expect(schema).not_to be_valid
    end

    it "requires document_type" do
      schema.document_type = nil
      expect(schema).not_to be_valid
    end

    it "requires raw_schema" do
      schema.raw_schema = nil
      expect(schema).not_to be_valid
    end

    it "enforces uniqueness on version + type + format" do
      schema.save!
      duplicate = described_class.new(
        oscal_version: "1.1.2",
        document_type: "ssp",
        schema_format: "json",
        raw_schema: sample_schema
      )
      expect(duplicate).not_to be_valid
    end
  end

  describe ".find_schema" do
    before { schema.save! }

    it "finds by document type and version" do
      result = described_class.find_schema(document_type: "ssp", oscal_version: "1.1.2")
      expect(result).to eq(schema)
    end

    it "accepts SPARC symbol types" do
      result = described_class.find_schema(document_type: :ssp, oscal_version: "1.1.2")
      expect(result).to eq(schema)
    end

    it "returns nil when not found" do
      result = described_class.find_schema(document_type: "ssp", oscal_version: "9.9.9")
      expect(result).to be_nil
    end

    it "excludes inactive schemas" do
      schema.update!(active: false)
      result = described_class.find_schema(document_type: "ssp", oscal_version: "1.1.2")
      expect(result).to be_nil
    end
  end

  describe ".find_schema!" do
    it "raises when not found" do
      expect {
        described_class.find_schema!(document_type: "ssp", oscal_version: "9.9.9")
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe ".resolve_document_type" do
    it "maps SPARC symbols to OSCAL types" do
      expect(described_class.resolve_document_type(:component_definition)).to eq("component-definition")
      expect(described_class.resolve_document_type(:ssp)).to eq("ssp")
      expect(described_class.resolve_document_type(:assessment_plan)).to eq("assessment-plan")
      expect(described_class.resolve_document_type(:assessment_results)).to eq("assessment-results")
      expect(described_class.resolve_document_type(:poam)).to eq("poam")
    end

    it "passes through string types unchanged" do
      expect(described_class.resolve_document_type("ssp")).to eq("ssp")
      expect(described_class.resolve_document_type("component-definition")).to eq("component-definition")
    end
  end

  describe ".nist_url" do
    it "builds the correct NIST download URL (#453: GitHub release-asset path)" do
      url = described_class.nist_url("1.1.2", "ssp")
      expect(url).to eq("https://github.com/usnistgov/OSCAL/releases/download/v1.1.2/oscal_ssp_schema.json")
    end

    it "uses the NIST-published filename for component-definition (#453)" do
      # NIST emits the component-definition schema as `oscal_component_schema.json`
      # (no hyphen) — fixed in #453 after pre-existing 404s every fetch.
      url = described_class.nist_url("1.1.2", "component-definition")
      expect(url).to end_with("oscal_component_schema.json")
    end

    it "returns nil for unknown document types" do
      expect(described_class.nist_url("1.1.2", "unknown")).to be_nil
    end
  end

  describe "#ensure_preprocessed!" do
    it "computes and stores preprocessed schema" do
      schema.save!
      expect(schema.preprocessed_schema).to be_nil

      schema.ensure_preprocessed!

      expect(schema.preprocessed_schema).to be_present
      expect(schema.preprocessed_schema).not_to have_key("$id")
    end

    it "rewrites anchor refs to JSON Pointer format" do
      schema.save!
      schema.ensure_preprocessed!

      ref = schema.preprocessed_schema.dig("properties", "system-security-plan", "$ref")
      expect(ref).to eq("#/definitions/assembly_oscal-ssp_system-security-plan")
    end

    it "strips fragment $id values from definitions" do
      schema.save!
      schema.ensure_preprocessed!

      defn = schema.preprocessed_schema.dig("definitions", "assembly_oscal-ssp_system-security-plan")
      expect(defn).not_to have_key("$id")
    end

    it "returns existing preprocessed schema without recomputing" do
      schema.preprocessed_schema = { "cached" => true }
      schema.save!

      result = schema.ensure_preprocessed!
      expect(result).to eq({ "cached" => true })
    end
  end

  describe "#compute_checksum" do
    it "returns SHA256 hex digest of raw schema" do
      expected = Digest::SHA256.hexdigest(sample_schema.to_json)
      expect(schema.compute_checksum).to eq(expected)
    end
  end

  describe ".preprocess_schema" do
    it "removes top-level $id" do
      result = described_class.preprocess_schema(sample_schema)
      expect(result).not_to have_key("$id")
    end

    it "rewrites anchor $refs to JSON Pointers" do
      result = described_class.preprocess_schema(sample_schema)
      ref = result.dig("properties", "system-security-plan", "$ref")
      expect(ref).to eq("#/definitions/assembly_oscal-ssp_system-security-plan")
    end
  end

  describe "constants" do
    it "has 5 supported versions" do
      expect(OscalSchema::SUPPORTED_VERSIONS).to eq(%w[1.1.1 1.1.2 1.1.3 1.2.0 1.2.1])
    end

    it "has 8 document types" do
      expect(OscalSchema::DOCUMENT_TYPE_MAP.keys.length).to eq(8)
    end

    it "maps all SPARC symbols" do
      OscalSchema::SPARC_TYPE_MAP.each do |symbol, oscal_type|
        expect(OscalSchema::DOCUMENT_TYPE_MAP).to have_key(oscal_type),
          "SPARC symbol :#{symbol} maps to '#{oscal_type}' which is not in DOCUMENT_TYPE_MAP"
      end
    end
  end
end
