require "rails_helper"

RSpec.describe ProfileJsonParserService, "resolved profile catalog parsing" do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/profiles/small-resolved-profile-catalog.json") }
  let(:document) { create(:profile_document, file_type: "json", status: "processing") }
  let(:service) { described_class.new(document, fixture_path.to_s) }

  describe "#parse with resolved profile catalog" do
    before { service.parse; document.reload }

    it "detects and parses a resolved profile catalog" do
      expect(document.status).not_to eq("failed")
    end

    it "creates controls from groups" do
      # 4 controls: ac-1, ac-2, ac-2.1 (enhancement), au-1
      expect(document.profile_controls.count).to eq(4)
    end

    it "extracts control IDs from group controls" do
      ids = document.profile_controls.pluck(:control_id).sort
      expect(ids).to eq(%w[ac-1 ac-2 ac-2.1 au-1])
    end

    it "extracts control titles (resolved profiles include titles)" do
      titles = document.profile_controls.pluck(:title).compact
      expect(titles).to include("Policy and Procedures", "Account Management", "Event Logging Policy and Procedures")
    end

    it "extracts nested control enhancements" do
      enhancement = document.profile_controls.find_by(control_id: "ac-2.1")
      expect(enhancement).to be_present
      expect(enhancement.title).to eq("Automated System Account Management")
    end

    it "assigns control families from group ID" do
      families = document.profile_controls.pluck(:control_family).uniq.sort
      expect(families).to eq(%w[AC AU])
    end

    it "stores props as control fields" do
      ac1 = document.profile_controls.find_by(control_id: "ac-1")
      label_field = ac1.profile_control_fields.find_by(field_name: "prop:label")
      expect(label_field&.field_value).to eq("AC-1")
    end

    it "stores parameters as control fields" do
      ac1 = document.profile_controls.find_by(control_id: "ac-1")
      param_label = ac1.profile_control_fields.find_by(field_name: "parameter_label:ac-01_odp.01")
      expect(param_label&.field_value).to eq("personnel or roles")
    end

    it "stores parameter guidelines as control fields" do
      ac1 = document.profile_controls.find_by(control_id: "ac-1")
      guideline = ac1.profile_control_fields.find_by("field_name LIKE 'parameter_guideline:ac-01_odp.01%'")
      expect(guideline&.field_value).to include("disseminated")
    end

    it "detects baseline level from title" do
      expect(document.baseline_level).to eq("LOW")
    end

    it "sets profile version from metadata" do
      expect(document.profile_version).to eq("5.2.0")
    end

    it "sets OSCAL version from metadata" do
      expect(document.oscal_version).to eq("1.1.3")
    end

    it "stores resolved catalog JSON directly" do
      expect(document.resolved_catalog_json).to be_present
      expect(document.resolved_catalog_json).to have_key("catalog")
    end

    it "sets import_metadata format to oscal_resolved_profile" do
      expect(document.import_metadata["format"]).to eq("oscal_resolved_profile")
    end

    it "stores source-profile href in import_metadata" do
      expect(document.import_metadata["source_profile_href"]).to include("LOW-baseline_profile")
    end

    it "sets auto_publish flag in metadata_extra" do
      expect(document.metadata_extra["auto_publish"]).to be true
    end

    it "preserves OSCAL metadata (roles, parties, responsible-parties)" do
      expect(document.metadata_extra["roles"]).to be_present
      expect(document.metadata_extra["parties"]).to be_present
      expect(document.metadata_extra["responsible-parties"]).to be_present
    end

    it "assigns the OSCAL UUID from the catalog" do
      expect(document.uuid).to eq("c7e4f8a2-3b91-4d5e-9a6c-8f2d1e0b7c34")
    end
  end

  describe "catalog auto-linking" do
    let!(:catalog) do
      create(:control_catalog,
        name: "NIST SP 800-53 Rev 5",
        status: "completed",
        lifecycle_status: "published")
    end

    it "links to matching catalog by source-profile href revision" do
      service.parse
      document.reload
      expect(document.control_catalog).to eq(catalog)
    end
  end

  describe "detection heuristic" do
    it "does not treat a regular catalog as a resolved profile" do
      # A plain catalog without resolution-tool or source-profile should not match
      plain_catalog = {
        "catalog" => {
          "uuid" => "test",
          "metadata" => { "title" => "Test Catalog" },
          "groups" => []
        }
      }

      tmp = Tempfile.new([ "plain_catalog_", ".json" ])
      tmp.write(JSON.generate(plain_catalog))
      tmp.close

      doc = create(:profile_document, file_type: "json", status: "processing")
      svc = described_class.new(doc, tmp.path)

      # Should raise because it's not a resolved profile and has no "profile" key
      expect { svc.parse }.to raise_error(/missing 'profile' root key/)
    ensure
      tmp&.unlink
    end

    it "detects by resolution-tool prop" do
      resolved_data = {
        "catalog" => {
          "uuid" => "test-uuid",
          "metadata" => {
            "title" => "Test MODERATE Resolved",
            "version" => "1.0.0",
            "oscal-version" => "1.1.2",
            "props" => [ { "name" => "resolution-tool", "value" => "TestTool" } ]
          },
          "groups" => []
        }
      }

      tmp = Tempfile.new([ "resolved_", ".json" ])
      tmp.write(JSON.generate(resolved_data))
      tmp.close

      doc = create(:profile_document, file_type: "json", status: "processing")
      svc = described_class.new(doc, tmp.path)

      expect { svc.parse }.not_to raise_error
      doc.reload
      expect(doc.import_metadata["format"]).to eq("oscal_resolved_profile")
    ensure
      tmp&.unlink
    end

    it "detects by source-profile link" do
      resolved_data = {
        "catalog" => {
          "uuid" => "test-uuid-2",
          "metadata" => {
            "title" => "Test HIGH Resolved",
            "version" => "2.0.0",
            "oscal-version" => "1.1.2",
            "links" => [ { "href" => "some_profile.xml", "rel" => "source-profile" } ]
          },
          "groups" => []
        }
      }

      tmp = Tempfile.new([ "resolved_", ".json" ])
      tmp.write(JSON.generate(resolved_data))
      tmp.close

      doc = create(:profile_document, file_type: "json", status: "processing")
      svc = described_class.new(doc, tmp.path)

      expect { svc.parse }.not_to raise_error
      doc.reload
      expect(doc.import_metadata["format"]).to eq("oscal_resolved_profile")
      expect(doc.baseline_level).to eq("HIGH")
    ensure
      tmp&.unlink
    end
  end
end

RSpec.describe DocumentConversionJob, "auto-publish for resolved profiles" do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/profiles/small-resolved-profile-catalog.json") }

  # #392: persist the blob so post-perform assertions can still inspect it
  # if needed; the production default purges after success.
  before { ENV["SPARC_PERSIST_S3_BLOB"] = "true" }
  after  { ENV.delete("SPARC_PERSIST_S3_BLOB") }

  it "auto-publishes resolved profiles with auto_publish flag" do
    document = create(:profile_document, file_type: "json", status: "pending")
    document.file.attach(io: File.open(fixture_path), filename: "small-resolved-profile-catalog.json", content_type: "application/json")

    DocumentConversionJob.new.perform(:profile, document.id)
    document.reload

    expect(document.status).to eq("completed")
    expect(document.lifecycle_status).to eq("published")
    expect(document.published).to be_present
  end

  it "does not auto-publish regular profiles" do
    fixture = Rails.root.join("spec/fixtures/files/profiles/NIST_SP-800-53_rev5_LOW-baseline_profile.json")
    document = create(:profile_document, file_type: "json", status: "pending")
    document.file.attach(io: File.open(fixture), filename: "NIST_SP-800-53_rev5_LOW-baseline_profile.json", content_type: "application/json")

    DocumentConversionJob.new.perform(:profile, document.id)
    document.reload

    expect(document.status).to eq("completed")
    expect(document.lifecycle_status).to eq("in_progress")
  end
end

RSpec.describe ProfileXmlParserService, "resolved profile catalog XML" do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/profiles/NIST_SP-800-53_rev4_MODERATE-baseline-resolved-profile_catalog.xml") }
  let(:document) { create(:profile_document, file_type: "xml", status: "processing") }
  let(:service) { described_class.new(document, fixture_path.to_s) }

  describe "#parse with resolved catalog XML" do
    before { service.parse; document.reload }

    it "detects and parses a resolved catalog XML" do
      expect(document.import_metadata["format"]).to eq("oscal_resolved_profile")
    end

    it "creates controls from groups" do
      expect(document.profile_controls.count).to be > 0
    end

    it "sets auto_publish flag" do
      expect(document.metadata_extra["auto_publish"]).to be true
    end

    it "stores resolved catalog JSON" do
      expect(document.resolved_catalog_json).to be_present
      expect(document.resolved_catalog_json).to have_key("catalog")
    end
  end
end
