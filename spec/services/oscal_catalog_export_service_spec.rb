require "rails_helper"

RSpec.describe OscalCatalogExportService do
  let(:catalog) do
    create(:control_catalog,
           name: "NIST SP 800-53 Rev 5",
           version: "5.1.1",
           oscal_version: "1.1.2",
           published: "2024-01-15T00:00:00Z",
           metadata_extra: {
             "roles" => [ { "id" => "creator", "title" => "Document Creator" } ],
             "parties" => [ { "uuid" => "test-uuid", "type" => "organization", "name" => "NIST" } ]
           })
  end

  let(:family) do
    create(:control_family, control_catalog: catalog, code: "AC", name: "Access Control", sort_order: 1)
  end

  before do
    family.catalog_controls.create!(
      control_id: "AC-01",
      title: "Policy and Procedures",
      priority: "P1",
      baseline_impact: "LOW, MODERATE, HIGH",
      guidance_data: {
        "statement" => "Develop and document access control policy.",
        "supplemental_guidance" => "This control addresses policy requirements.",
        "related_controls" => "AC-02, AC-03"
      }
    )
  end

  subject { described_class.new(catalog) }

  describe "#export_unvalidated" do
    it "produces valid JSON with catalog root key" do
      json = subject.export_unvalidated
      data = JSON.parse(json)

      expect(data).to have_key("catalog")
      cat = data["catalog"]
      expect(cat["metadata"]["title"]).to eq("NIST SP 800-53 Rev 5")
      expect(cat["metadata"]["oscal-version"]).to eq("1.1.2")
      expect(cat["metadata"]["version"]).to eq("5.1.1")
      expect(cat["metadata"]["published"]).to eq("2024-01-15T00:00:00Z")
    end

    it "includes metadata_extra roles and parties" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      metadata = data["catalog"]["metadata"]

      expect(metadata["roles"]).to be_an(Array)
      expect(metadata["roles"].first["id"]).to eq("creator")
      expect(metadata["parties"]).to be_an(Array)
      expect(metadata["parties"].first["name"]).to eq("NIST")
    end

    it "includes groups with controls" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      groups = data["catalog"]["groups"]

      expect(groups.size).to eq(1)
      expect(groups.first["id"]).to eq("ac")
      expect(groups.first["title"]).to eq("Access Control")

      controls = groups.first["controls"]
      expect(controls.size).to eq(1)
      expect(controls.first["title"]).to eq("Policy and Procedures")
    end

    it "includes control props and parts" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      control = data["catalog"]["groups"].first["controls"].first

      props = control["props"]
      expect(props.map { |p| p["name"] }).to include("label", "priority", "impact-level")

      parts = control["parts"]
      expect(parts.size).to eq(2)
      expect(parts.map { |p| p["name"] }).to contain_exactly("statement", "guidance")
    end
  end

  describe "#validation_result" do
    it "returns a result object" do
      result = subject.validation_result
      expect(result).to respond_to(:valid?)
      expect(result).to respond_to(:errors)
    end
  end
end
