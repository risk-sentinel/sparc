# frozen_string_literal: true

require "rails_helper"

# #1252 — OSCAL groups at any depth. A catalog whose controls sit in nested
# groups (NIST's example catalog: `s1` → `s1.1` → `s1.1.1`) imported with no
# controls and no reason. It now imports every control into the family of its
# top-level group, records the nested group each sits in, exports the groups
# as the file had them, and heads them on the family page.
RSpec.describe "Catalog nested groups (#1252)" do
  let(:examples) { Rails.root.join("spec/fixtures/files/profiles/nist_examples") }

  def import(path)
    CatalogImportService.call(File.open(path), File.basename(path))[:catalog]
  end

  def import_json(data)
    path = Rails.root.join("tmp", "nested-#{SecureRandom.hex(4)}.json")
    File.write(path, JSON.generate(data))
    import(path)
  ensure
    FileUtils.rm_f(path)
  end

  def rows(catalog)
    CatalogControl.joins(:control_family).where(control_families: { control_catalog_id: catalog.id }, statement_item: false)
                  .pluck("control_families.code", :control_id, :group_id).sort
  end

  # A group tree with each group's own fields and its control ids, so two
  # catalogs compare by structure rather than by every control's content.
  def group_tree(groups)
    Array(groups).map do |group|
      group.slice(*CatalogGroupTree::FIELDS)
           .merge("groups" => group_tree(group["groups"]), "controls" => Array(group["controls"]).map { |c| c["id"] })
    end
  end

  let(:basic_json) { JSON.parse(examples.join("basic_catalog.json").read) }

  %w[json xml].each do |format|
    describe "NIST's example catalog in #{format.upcase}" do
      let!(:catalog) { import(examples.join("basic_catalog.#{format}")) }

      it "imports every control into its top-level group's family, recording its nested group" do
        expect(rows(catalog)).to eq([
          [ "S1", "s1.1.1", "s1.1" ], [ "S1", "s1.1.2", "s1.1" ],
          [ "S2", "s2.1.1", "s2.1" ], [ "S2", "s2.1.2", "s2.1" ]
        ])
      end

      it "exports the groups as the file has them, and the export is schema-valid" do
        exported = JSON.parse(OscalCatalogExportService.new(catalog).export_unvalidated)

        expect(group_tree(exported.dig("catalog", "groups"))).to eq(group_tree(basic_json.dig("catalog", "groups")))
        result = OscalSchemaValidationService.validate(:catalog, exported, version: OscalSchema::DEFAULT_VERSION)
        expect(result.errors).to eq([])
      end
    end
  end

  it "NIST's example profile selects from it as NIST intends" do
    catalog = import(examples.join("basic_catalog.json"))
    import_spec = JSON.parse(examples.join("basic_profile.json").read).dig("profile", "imports", 0)

    # matching s1.1.*, with-ids s2.1.1, exclude s2.1.2
    expect(ProfileSelection.new(CatalogControlTree.for(catalog)).select(import_spec))
      .to contain_exactly("s1.1.1", "s1.1.2", "s2.1.1")
  end

  describe "a nested group with no id" do
    let(:data) do
      { "catalog" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => { "title" => "Invented nested #{SecureRandom.hex(3)}", "last-modified" => "2026-10-23T00:00:00Z",
                        "version" => "1", "oscal-version" => "1.2.3" },
        "groups" => [ { "id" => "zz", "title" => "Invented family",
                        "controls" => [ { "id" => "zz-1", "title" => "Invented top" } ],
                        "groups" => [ { "title" => "Untitled section",
                                        "controls" => [ { "id" => "zz-2", "title" => "Invented nested" } ] } ] } ]
      } }
    end

    it "is keyed by its position and exported without that key" do
      catalog = import_json(data)

      expect(rows(catalog)).to eq([ [ "ZZ", "zz-1", nil ], [ "ZZ", "zz-2", "~1" ] ])
      exported = JSON.parse(OscalCatalogExportService.new(catalog).export_unvalidated)
      expect(group_tree(exported.dig("catalog", "groups"))).to eq(group_tree(data.dig("catalog", "groups")))
      expect(exported.dig("catalog", "groups", 0, "groups", 0)).not_to have_key("key")
    end
  end

  it "exports a control whose recorded group the family no longer has in the family's own group" do
    catalog = import(examples.join("basic_catalog.json"))
    family = catalog.control_families.find_by!(code: "S1")
    family.update!(group_data: family.group_data.except("groups"))

    exported = JSON.parse(OscalCatalogExportService.new(catalog).export_unvalidated)
    s1 = exported.dig("catalog", "groups").find { |g| g["id"] == "s1" }
    expect(s1["controls"].map { |c| c["id"] }).to eq(%w[s1.1.1 s1.1.2])
  end

  it "refuses a catalog whose groups hold no control at any depth, writing nothing" do
    empty = basic_json.deep_dup
    empty["catalog"]["groups"].each { |g| g["groups"].each { |sub| sub.delete("controls") } }

    before = ControlCatalog.count
    expect { import_json(empty) }.to raise_error(CatalogImportService::ImportError, /no controls at any depth/)
    expect(ControlCatalog.count).to eq(before)
  end

  describe "the family page", type: :request do
    it "heads each nested group's controls" do
      sign_in_as(create(:user, :admin))
      catalog = import(examples.join("basic_catalog.json"))

      get control_family_path(catalog.control_families.find_by!(code: "S2"))
      follow_redirect! while response.redirect?

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      headings = page.css("[data-testid='catalog-subgroup-heading']").map { |h| h.text.squish }
      expect(headings).to eq([ "Business requirements of access control s2.1" ])
      rows_after = page.css("[data-testid='catalog-subgroup-heading'] ~ tr").map { |tr| tr["data-control-db-id"] }.compact
      expect(rows_after.size).to eq(2)
    end
  end
end
