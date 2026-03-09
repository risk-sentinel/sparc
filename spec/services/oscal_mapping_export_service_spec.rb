require "rails_helper"

RSpec.describe OscalMappingExportService do
  let(:source_catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 5", version: "5.1.1") }
  let(:target_catalog) { create(:control_catalog, name: "ISO 27001:2022", version: "2022") }

  let(:mapping) do
    create(:control_mapping,
           name: "NIST to ISO Mapping",
           description: "Cross-walk between NIST 800-53 and ISO 27001",
           status: "draft",
           method_type: "human",
           matching_rationale: "semantic",
           mapping_version: "1.0.0",
           source_catalog: source_catalog,
           target_catalog: target_catalog)
  end

  let!(:entry1) do
    create(:control_mapping_entry,
           control_mapping: mapping,
           source_control_id: "AC-1",
           target_control_id: "A.5.1",
           relationship: "equivalent",
           remarks: "Both address access control policy",
           row_order: 1)
  end

  let!(:entry2) do
    create(:control_mapping_entry,
           control_mapping: mapping,
           source_control_id: "AC-2",
           target_control_id: "A.5.15",
           relationship: "subset",
           row_order: 2)
  end

  subject { described_class.new(mapping) }

  describe "#export_unvalidated" do
    it "produces valid JSON with mapping-collection root key" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      expect(data).to have_key("mapping-collection")
    end

    it "includes metadata with title and version" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      metadata = data["mapping-collection"]["metadata"]

      expect(metadata["title"]).to eq("NIST to ISO Mapping")
      expect(metadata["version"]).to eq("1.0.0")
      expect(metadata["oscal-version"]).to eq("1.2.1")
      expect(metadata["last-modified"]).to be_present
    end

    it "includes provenance with method, rationale, and status" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      provenance = data["mapping-collection"]["provenance"]

      expect(provenance["method"]).to eq("human")
      expect(provenance["matching-rationale"]).to eq("semantic")
      expect(provenance["status"]).to eq("draft")
      expect(provenance["mapping-description"]).to include("Cross-walk")
    end

    it "includes mappings array with source and target resources" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      mappings = data["mapping-collection"]["mappings"]

      expect(mappings).to be_an(Array)
      expect(mappings.size).to eq(1)
      expect(mappings.first["source-resource"]["type"]).to eq("catalog")
      expect(mappings.first["target-resource"]["type"]).to eq("catalog")
    end

    it "includes maps with correct source and target control IDs" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      maps = data["mapping-collection"]["mappings"].first["maps"]

      expect(maps.size).to eq(2)

      first_map = maps.first
      expect(first_map["relationship"]).to eq("equivalent")
      expect(first_map["sources"].first["id-ref"]).to eq("ac-1")
      expect(first_map["targets"].first["id-ref"]).to eq("a.5.1")
      expect(first_map["remarks"]).to eq("Both address access control policy")

      second_map = maps.second
      expect(second_map["relationship"]).to eq("subset")
      expect(second_map["sources"].first["id-ref"]).to eq("ac-2")
    end

    it "includes back-matter with catalog resources" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      resources = data["mapping-collection"]["back-matter"]["resources"]

      expect(resources.size).to eq(2)
      titles = resources.map { |r| r["title"] }
      expect(titles).to include("NIST SP 800-53 Rev 5")
      expect(titles).to include("ISO 27001:2022")
    end

    it "normalizes control IDs to lowercase" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      maps = data["mapping-collection"]["mappings"].first["maps"]

      maps.each do |map|
        map["sources"].each { |s| expect(s["id-ref"]).to eq(s["id-ref"].downcase) }
        map["targets"].each { |t| expect(t["id-ref"]).to eq(t["id-ref"].downcase) }
      end
    end
  end

  describe "#validation_result" do
    it "returns a result object with valid? and errors" do
      result = subject.validation_result
      expect(result).to respond_to(:valid?)
      expect(result).to respond_to(:errors)
    end
  end

  describe "with empty entries" do
    let(:empty_mapping) do
      create(:control_mapping,
             name: "Empty Mapping",
             source_catalog: source_catalog,
             target_catalog: target_catalog)
    end

    subject { described_class.new(empty_mapping) }

    it "produces JSON with an empty maps array" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      maps = data["mapping-collection"]["mappings"].first["maps"]
      expect(maps).to eq([])
    end
  end
end
