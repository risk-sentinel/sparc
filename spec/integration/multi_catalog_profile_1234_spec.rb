# frozen_string_literal: true

require "rails_helper"

# #1234 — a profile that imports NIST SP 800-53 Rev 5 AND an organization's own
# catalog (docs/api/samples/custom-controls-{catalog,profile}.json). SPARC
# linked only the first import: the custom controls lost their titles, and the
# export listed them under the NIST import as though NIST published them.
RSpec.describe "A profile importing two catalogs (#1234)" do
  let(:fixtures) { Rails.root.join("spec/fixtures/files") }
  let(:samples) { Rails.root.join("docs/api/samples") }
  let(:profile_path) { samples.join("custom-controls-profile.json") }

  let!(:nist) do
    name = "NIST_SP-800-53_rev5_catalog.json"
    CatalogImportService.call(File.open(fixtures.join("catalogs", name)), name)[:catalog]
  end
  let!(:custom) do
    CatalogImportService.call(File.open(samples.join("custom-controls-catalog.json")), "custom-controls-catalog.json")[:catalog]
  end

  def import(path = profile_path)
    doc = create(:profile_document, status: "processing", file_type: "json", original_filename: File.basename(path),
                                    control_catalog: nil)
    ProfileJsonParserService.new(doc, path.to_s).parse
    doc.reload
  end

  def controls(doc) = doc.profile_controls.order(:row_order)

  describe "import" do
    it "links each control to the catalog its import names, and titles all five" do
      doc = import

      expect(doc.control_catalog).to eq(nist)
      expect(controls(doc).pluck(:control_id, :source_catalog_id)).to eq(
        [ [ "ac-1", nist.id ], [ "ac-2", nist.id ], [ "au-2", nist.id ], [ "dp-1", custom.id ], [ "dp-1.1", custom.id ] ]
      )
      expect(controls(doc).pluck(:title)).to all(be_present)
      expect(controls(doc).find_by(control_id: "dp-1").title).to eq("Data Retention Review")
    end

    it "keeps the custom catalog's parameter" do
      doc = import

      field = controls(doc).find_by(control_id: "dp-1").profile_control_fields.find_by(field_name: "parameter:dp-01_odp")
      expect(field&.field_value).to eq("quarterly")
    end

    it "records each import and how it was matched" do
      doc = import

      expect(doc.import_metadata["imports"].map { |i| [ i["catalog_id"], i["matched_by"] ] })
        .to eq([ [ nist.id, "nist_pattern" ], [ custom.id, "title" ] ])
      expect(doc.import_metadata).not_to have_key("unlinked_imports")
    end

    it "links a profile importing only the custom catalog to that catalog" do
      only_custom = JSON.parse(File.read(profile_path))
      only_custom["profile"]["imports"].shift
      path = Rails.root.join("tmp", "only-custom-#{SecureRandom.hex(4)}.json")
      File.write(path, JSON.generate(only_custom))

      doc = import(path)

      expect(doc.control_catalog).to eq(custom)
      expect(controls(doc).pluck(:title)).to all(be_present)
    ensure
      FileUtils.rm_f(path) if path
    end

    it "links the first import that resolves when the first one names no loaded catalog" do
      data = JSON.parse(File.read(profile_path))
      nist_resource = data.dig("profile", "back-matter", "resources").first
      nist_resource["title"] = "A catalog this instance never loaded"
      nist_resource["rlinks"] = [ { "href" => "https://example.com/unknown.json" } ]
      path = Rails.root.join("tmp", "first-unlinked-#{SecureRandom.hex(4)}.json")
      File.write(path, JSON.generate(data))

      doc = import(path)

      expect(doc.control_catalog).to eq(custom)
      expect(doc.import_metadata["unlinked_imports"].map { |i| i["control_ids"] }).to eq([ %w[ac-1 ac-2 au-2] ])
    ensure
      FileUtils.rm_f(path) if path
    end

    it "leaves an import unlinked, and says so, when two catalogs share its title" do
      create(:control_catalog, name: custom.name)

      doc = import

      expect(controls(doc).where(control_id: %w[dp-1 dp-1.1]).pluck(:source_catalog_id)).to all(be_nil)
      expect(doc.import_metadata["unlinked_imports"].map { |i| i["control_ids"] }).to eq([ %w[dp-1 dp-1.1] ])
    end
  end

  describe "export" do
    it "writes one import per catalog, each selecting its own controls, and validates" do
      doc = import
      exported = JSON.parse(OscalProfileExportService.new(doc).export)

      imports = exported.dig("profile", "imports")
      expect(imports.map { |i| [ i["href"], i.dig("include-controls", 0, "with-ids") ] }).to eq(
        [ [ "uuid:#{nist.oscal_uuid}", %w[ac-1 ac-2 au-2] ], [ "uuid:#{custom.oscal_uuid}", %w[dp-1 dp-1.1] ] ]
      )
      resources = exported.dig("profile", "back-matter", "resources").map { |r| r["uuid"] }
      expect(resources).to include(nist.oscal_uuid, custom.oscal_uuid)
      expect(OscalSchemaValidationService.validate(:profile, exported, version: "1.2.3").errors).to be_empty
    end

    it "keeps dp-01_odp = quarterly through the round trip" do
      doc = import
      exported = JSON.parse(OscalProfileExportService.new(doc).export)

      expect(exported.dig("profile", "modify", "set-parameters"))
        .to include({ "param-id" => "dp-01_odp", "values" => [ "quarterly" ] })
    end
  end

  describe "resolution" do
    it "includes the custom controls with their statements and parameters" do
      doc = import
      resolved = JSON.parse(OscalResolvedProfileCatalogService.new(doc).export)

      groups = resolved.dig("catalog", "groups").index_by { |g| g["id"] }
      expect(groups.keys).to include("ac", "au", "dp")
      dp1 = groups["dp"]["controls"].find { |c| c["id"] == "dp-1" }
      expect(dp1["parts"].map { |p| p["name"] }).to include("statement")
      # Resolution states a set value as the parameter's label, as it does for NIST's.
      expect(dp1["params"].find { |p| p["id"] == "dp-01_odp" }["label"]).to eq("quarterly")
      expect(dp1["controls"].map { |c| c["id"] }).to eq([ "dp-1.1" ])
      expect(resolved.dig("catalog", "back-matter", "resources").map { |r| r["uuid"] })
        .to include(nist.oscal_uuid, custom.oscal_uuid)
    end
  end

  # A single-catalog NIST profile must import and export exactly as before.
  describe "a single-catalog NIST profile" do
    it "has one import naming the NIST catalog, every control sourced from it" do
      path = fixtures.join("profiles/NIST_SP-800-53_rev5_MODERATE-tailored_profile.json")
      doc = import(path)
      exported = JSON.parse(OscalProfileExportService.new(doc).export)

      expect(doc.control_catalog).to eq(nist)
      expect(doc.profile_controls.distinct.pluck(:source_catalog_id)).to eq([ nist.id ])
      expect(exported.dig("profile", "imports").size).to eq(1)
      expect(exported.dig("profile", "imports", 0, "href")).to eq("uuid:#{nist.oscal_uuid}")
    end
  end
end

# #1234 — owner, 2026-10-21: JSON, YAML and XML must all be honoured. The same
# two-catalog profile in each format links each import to its own catalog.
RSpec.describe "A two-catalog profile in every format (#1234)" do
  let(:fixtures) { Rails.root.join("spec/fixtures/files") }
  let(:samples) { Rails.root.join("docs/api/samples") }
  let(:data) { JSON.parse(File.read(samples.join("custom-controls-profile.json"))) }

  let!(:nist) do
    name = "NIST_SP-800-53_rev5_catalog.json"
    CatalogImportService.call(File.open(fixtures.join("catalogs", name)), name)[:catalog]
  end
  let!(:custom) do
    CatalogImportService.call(File.open(samples.join("custom-controls-catalog.json")), "custom-controls-catalog.json")[:catalog]
  end

  def import_as(ext, content, parser)
    path = Rails.root.join("tmp", "two-catalog-#{SecureRandom.hex(4)}.#{ext}")
    File.write(path, content)
    doc = create(:profile_document, status: "processing", file_type: ext, original_filename: File.basename(path),
                                    control_catalog: nil)
    parser.new(doc, path.to_s).parse
    doc.reload
  ensure
    FileUtils.rm_f(path) if path
  end

  def expect_both_catalogs_linked(doc)
    expect(doc.control_catalog).to eq(nist)
    expect(doc.profile_controls.order(:row_order).pluck(:control_id, :source_catalog_id)).to eq(
      [ [ "ac-1", nist.id ], [ "ac-2", nist.id ], [ "au-2", nist.id ], [ "dp-1", custom.id ], [ "dp-1.1", custom.id ] ]
    )
    expect(doc.profile_controls.pluck(:title)).to all(be_present)
    dp1 = doc.profile_controls.find_by(control_id: "dp-1")
    expect(dp1.profile_control_fields.find_by(field_name: "parameter:dp-01_odp")&.field_value).to eq("quarterly")
  end

  it "imports from YAML" do
    expect_both_catalogs_linked(import_as("yaml", data.to_yaml, ProfileYamlParserService))
  end

  it "imports from XML, and records that the file was XML" do
    xml = OscalJsonToXmlConverter.new(:profile, data).convert
    expect(OscalSchemaValidationService.validate_xml(:profile, xml).errors).to be_empty

    doc = import_as("xml", xml, ProfileXmlParserService)

    expect_both_catalogs_linked(doc)
    expect(doc.import_metadata["format"]).to eq("oscal_profile_xml")
    expect(doc.import_metadata["imports"].size).to eq(2)
  end
end
