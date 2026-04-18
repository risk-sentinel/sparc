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
             "parties" => [ { "uuid" => SecureRandom.uuid, "type" => "organization", "name" => "NIST" } ]
           })
  end

  let(:family) do
    create(:control_family, control_catalog: catalog, code: "AC", name: "Access Control", sort_order: 1)
  end

  before do
    family.catalog_controls.create!(
      control_id: "ac-1",
      label: "AC-1",
      sort_id: "ac-01",
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

  it_behaves_like "produces stable UUIDs across exports"

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

  describe "enhancement nesting" do
    before do
      # Base control ac-2
      family.catalog_controls.create!(
        control_id: "ac-2",
        label: "AC-2",
        sort_id: "ac-02",
        title: "Account Management",
        priority: "P1",
        baseline_impact: "LOW, MODERATE, HIGH",
        guidance_data: {
          "statement" => "Manage information system accounts.",
          "supplemental_guidance" => "Account management includes establishing accounts.",
          "related_controls" => "AC-03, AC-04"
        }
      )

      # Enhancement ac-2.1
      family.catalog_controls.create!(
        control_id: "ac-2.1",
        label: "AC-2(1)",
        sort_id: "ac-02.01",
        title: "Automated System Account Management",
        baseline_impact: "MODERATE, HIGH",
        guidance_data: {
          "statement" => "Employ automated mechanisms to support management of accounts.",
          "supplemental_guidance" => "Automated account management reduces risk."
        }
      )

      # Enhancement ac-2.2
      family.catalog_controls.create!(
        control_id: "ac-2.2",
        label: "AC-2(2)",
        sort_id: "ac-02.02",
        title: "Automated Temporary and Emergency Account Management",
        baseline_impact: "MODERATE, HIGH",
        guidance_data: {
          "statement" => "Automatically remove or disable temporary and emergency accounts."
        }
      )
    end

    it "nests enhancements under their parent control" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      controls = data["catalog"]["groups"].first["controls"]

      # Only base controls appear at the top level
      top_level_ids = controls.map { |c| c["id"] }
      expect(top_level_ids).to contain_exactly("ac-1", "ac-2")

      # Enhancements should NOT appear at the top level
      expect(top_level_ids).not_to include("ac-2.1", "ac-2.2")
    end

    it "places enhancements in the parent's controls array" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      ac2 = data["catalog"]["groups"].first["controls"].find { |c| c["id"] == "ac-2" }

      expect(ac2).to have_key("controls")
      nested_ids = ac2["controls"].map { |c| c["id"] }
      expect(nested_ids).to contain_exactly("ac-2.1", "ac-2.2")
    end

    it "includes full control data for nested enhancements" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      ac2 = data["catalog"]["groups"].first["controls"].find { |c| c["id"] == "ac-2" }
      enh1 = ac2["controls"].find { |c| c["id"] == "ac-2.1" }

      expect(enh1["title"]).to eq("Automated System Account Management")
      expect(enh1["props"].map { |p| p["name"] }).to include("label")
      expect(enh1["parts"]).to be_present
    end

    it "does not add controls key when a base control has no enhancements" do
      json = subject.export_unvalidated
      data = JSON.parse(json)
      ac1 = data["catalog"]["groups"].first["controls"].find { |c| c["id"] == "ac-1" }

      expect(ac1).not_to have_key("controls")
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
