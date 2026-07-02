require "rails_helper"

RSpec.describe DataMappingSchema do
  describe ".load" do
    it "loads the SSP Excel mapping schema" do
      schema = described_class.load(:ssp_excel)
      expect(schema.format).to eq("ssp_excel")
      expect(schema.document_type).to eq("SspDocument")
      expect(schema.control_type).to eq("SspControl")
      expect(schema.field_type).to eq("SspControlField")
    end

    it "loads the SAR Excel mapping schema" do
      schema = described_class.load(:sar_excel)
      expect(schema.format).to eq("sar_excel")
      expect(schema.document_type).to eq("SarDocument")
      expect(schema.control_type).to eq("SarControl")
      expect(schema.field_type).to eq("SarControlField")
    end

    it "raises SchemaNotFound for unknown mappings" do
      expect { described_class.load(:nonexistent) }.to raise_error(DataMappingSchema::SchemaNotFound)
    end
  end

  describe ".available" do
    it "returns available schema names" do
      schemas = described_class.available
      expect(schemas).to include(:ssp_excel, :sar_excel)
    end
  end

  describe "#column_map" do
    context "SSP Excel" do
      let(:schema) { described_class.load(:ssp_excel) }

      it "produces a column map compatible with SspExcelParserService" do
        map = schema.column_map
        expect(map["control-id"]).to eq({ key: :control_id, control_attr: true })
        expect(map["control-title"]).to eq({ key: :title, control_attr: true })
        expect(map["implementation-status"]).to eq({ key: "status", control_attr: false })
        expect(map["remarks"]).to eq({ key: "notes", control_attr: false })
      end

      it "includes all 17 SSP fields" do
        expect(schema.column_map.size).to eq(17)
      end
    end

    context "SAR Excel" do
      let(:schema) { described_class.load(:sar_excel) }

      it "produces a column map compatible with SarExcelParserService" do
        map = schema.column_map
        expect(map["control-id"]).to eq({ key: :control_id, control_attr: true })
        expect(map["objective-title"]).to eq({ key: :title, control_attr: true })
        expect(map["subject"]).to eq({ key: :subject, control_attr: :subject })
        expect(map["finding-result"]).to eq({ key: "result", control_attr: false })
      end

      it "includes all 23 SAR fields" do
        expect(schema.column_map.size).to eq(23)
      end
    end
  end

  describe "#editable_fields" do
    it "returns SSP editable field keys matching SspControlField::EDITABLE_FIELDS" do
      schema = described_class.load(:ssp_excel)
      editable = schema.editable_fields
      expect(editable).to include("status", "implementation_statement", "implementation_summary",
                                  "notes", "expected_completion", "responsible_entities",
                                  "control_application", "coverage_level", "control_type")
    end

    it "returns SAR editable field keys matching SarControlField::EDITABLE_FIELDS" do
      schema = described_class.load(:sar_excel)
      editable = schema.editable_fields
      expect(editable).to include("date", "result", "notes_weakness", "recommended_fix",
                                  "test_text", "expected_result", "custom", "custom_name",
                                  "custom_author", "working_comments", "working_status")
    end
  end

  describe "#field_definition" do
    let(:schema) { described_class.load(:ssp_excel) }

    it "returns the full definition for a known field" do
      defn = schema.field_definition("status")
      expect(defn["key"]).to eq("status")
      expect(defn["editable"]).to be true
      expect(defn["storage"]).to eq("control_field")
      expect(defn["validation"]).to be_present
    end

    it "returns nil for an unknown field" do
      expect(schema.field_definition("nonexistent")).to be_nil
    end
  end

  describe "#oscal_mappings" do
    let(:schema) { described_class.load(:ssp_excel) }

    it "returns OSCAL mappings for fields that have them" do
      mappings = schema.oscal_mappings
      expect(mappings).to have_key("status")
      expect(mappings["status"]["target"]).to eq("prop")
      expect(mappings["status"]["prop_name"]).to eq("implementation-status")
    end

    it "includes statement-type mappings" do
      mappings = schema.oscal_mappings
      expect(mappings["implementation_statement"]["target"]).to eq("statement")
      expect(mappings["implementation_summary"]["target"]).to eq("statement")
    end

    it "includes remarks-type mappings" do
      mappings = schema.oscal_mappings
      expect(mappings["notes"]["target"]).to eq("remarks")
      expect(mappings["history"]["target"]).to eq("remarks")
    end
  end

  describe "#allowed_values_for" do
    let(:schema) { described_class.load(:ssp_excel) }

    it "returns allowed values for constrained fields" do
      values = schema.allowed_values_for("status")
      expect(values).to eq([ "Deferred", "Implemented", "Not Applicable", "Will Not Implement" ])
    end

    it "returns nil for unconstrained fields" do
      expect(schema.allowed_values_for("notes")).to be_nil
    end
  end

  describe "schema validation" do
    it "raises InvalidSchema for missing format" do
      data = { "version" => "1.0", "document_type" => "X", "control_type" => "Y",
               "field_type" => "Z", "fields" => [ { "key" => "a", "source_header" => "b", "storage" => "control_field" } ] }
      expect { described_class.new(data) }.to raise_error(DataMappingSchema::InvalidSchema, /format/)
    end

    it "raises InvalidSchema for empty fields" do
      data = { "format" => "test", "version" => "1.0", "document_type" => "X",
               "control_type" => "Y", "field_type" => "Z", "fields" => [] }
      expect { described_class.new(data) }.to raise_error(DataMappingSchema::InvalidSchema, /empty/)
    end

    it "raises InvalidSchema for fields missing storage" do
      data = { "format" => "test", "version" => "1.0", "document_type" => "X",
               "control_type" => "Y", "field_type" => "Z",
               "fields" => [ { "key" => "a", "source_header" => "b" } ] }
      expect { described_class.new(data) }.to raise_error(DataMappingSchema::InvalidSchema, /storage/)
    end
  end

  describe "parser service integration" do
    it "SspExcelParserService::COLUMN_MAP matches schema-generated map" do
      schema_map = described_class.load(:ssp_excel).column_map
      expect(SspExcelParserService::COLUMN_MAP).to eq(schema_map)
    end

    it "SarExcelParserService::COLUMN_MAP matches schema-generated map" do
      schema_map = described_class.load(:sar_excel).column_map
      expect(SarExcelParserService::COLUMN_MAP).to eq(schema_map)
    end
  end
end
