# frozen_string_literal: true

require "rails_helper"

# #1252 — catalog_controls record which rows are OSCAL controls and which
# control each sits under. Import writes it from the tree; the backfill
# reconstructs it for older rows and must agree with what import writes;
# selection, the catalog export and the resolved profile read it, so a catalog
# whose ids are not NIST's (FedRAMP 20x style) works the same way.
RSpec.describe "Catalog control hierarchy (#1252)" do
  def import_json(data, name = "cat-#{SecureRandom.hex(4)}.json")
    path = Rails.root.join("tmp", name)
    File.write(path, JSON.generate(data))
    CatalogImportService.call(File.open(path), name)[:catalog]
  ensure
    FileUtils.rm_f(path)
  end

  def rows(catalog)
    CatalogControl.unscoped.joins(:control_family).where(control_families: { control_catalog_id: catalog.id })
                  .pluck(:control_id, :parent_control_id, :statement_item).sort
  end

  # The control tree of an OSCAL catalog document: child id => parent id.
  def oscal_tree(catalog_hash)
    tree = {}
    walk = lambda do |controls, parent|
      Array(controls).each do |c|
        tree[c["id"]] = parent
        walk.call(c["controls"], c["id"])
      end
    end
    Array(catalog_hash.dig("catalog", "groups")).each { |g| walk.call(g["controls"], nil) }
    tree
  end

  let(:ksi_style) do
    { "catalog" => {
      "uuid" => SecureRandom.uuid,
      "metadata" => { "title" => "Invented KSI-style #{SecureRandom.hex(3)}", "last-modified" => "2026-10-22T00:00:00Z",
                      "version" => "1", "oscal-version" => "1.2.3" },
      "groups" => [ { "id" => "ksi-auth", "title" => "Invented Authentication", "controls" => [
        { "id" => "ksi-auth-01", "title" => "Invented one" },
        { "id" => "ksi-auth-02", "title" => "Invented two",
          "controls" => [ { "id" => "ksi-auth-02-a", "title" => "Invented child" } ] }
      ] } ]
    } }
  end

  describe "NIST SP 800-53 Rev 5" do
    before(:all) do
      name = "NIST_SP-800-53_rev5_catalog.json"
      @nist_json = JSON.parse(File.read(Rails.root.join("spec/fixtures/files/catalogs", name)))
      @nist = CatalogImportService.call(File.open(Rails.root.join("spec/fixtures/files/catalogs", name)), name)[:catalog]
    end

    after(:all) { @nist&.destroy }

    it "import records every control and its parent exactly as NIST's tree has them" do
      controls = rows(@nist).reject(&:last).to_h { |id, parent, _| [ id, parent ] }
      expect(controls).to eq(oscal_tree(@nist_json))
    end

    it "import marks every other row as a statement item of a control" do
      items = rows(@nist).select(&:last)
      expect(items).not_to be_empty
      expect(items.map { |_, parent, _| parent }.uniq - oscal_tree(@nist_json).keys).to be_empty
    end

    it "the backfill reconstructs exactly what the import recorded" do
      recorded = rows(@nist)
      CatalogControl.unscoped.joins(:control_family).where(control_families: { control_catalog_id: @nist.id })
                    .update_all(parent_control_id: nil, statement_item: false)

      counts = CatalogHierarchyBackfill.new(@nist).run

      expect(rows(@nist)).to eq(recorded)
      expect(counts[:items_from_ids]).to eq(0)
    end

    it "the catalog export nests controls as NIST's catalog does" do
      exported = JSON.parse(OscalCatalogExportService.new(@nist).export_unvalidated)
      expect(oscal_tree(exported)).to eq(oscal_tree(@nist_json))
    end

    it "the selection tree is every control with its parent" do
      expect(CatalogControlTree.for(@nist).to_h).to eq(oscal_tree(@nist_json))
    end
  end

  describe "a catalog whose ids are not NIST's" do
    let!(:catalog) { import_json(ksi_style) }

    it "records its controls and nesting from the file" do
      expect(rows(catalog)).to eq([ [ "ksi-auth-01", nil, false ], [ "ksi-auth-02", nil, false ],
                                    [ "ksi-auth-02-a", "ksi-auth-02", false ] ])
    end

    it "the backfill leaves ids that extend nothing at the top level" do
      CatalogControl.unscoped.joins(:control_family).where(control_families: { control_catalog_id: catalog.id })
                    .update_all(parent_control_id: "x", statement_item: true)
      CatalogHierarchyBackfill.new(catalog).run
      expect(rows(catalog).map { |id, _, item| [ id, item ] }).to all(satisfy { |_, item| item == false })
    end

    it "exports every control, nested as the file had them" do
      exported = JSON.parse(OscalCatalogExportService.new(catalog).export_unvalidated)
      expect(oscal_tree(exported)).to eq(oscal_tree(ksi_style))
    end

    it "is listed by the top_level scope" do
      ids = CatalogControl.top_level.joins(:control_family)
                          .where(control_families: { control_catalog_id: catalog.id }).pluck(:control_id)
      expect(ids).to contain_exactly("ksi-auth-01", "ksi-auth-02", "ksi-auth-02-a")
    end

    it "include-all and with-child-controls select from it" do
      selection = ProfileSelection.new(CatalogControlTree.for(catalog))
      expect(selection.select({ "include-all" => {} })).to contain_exactly("ksi-auth-01", "ksi-auth-02", "ksi-auth-02-a")
      expect(selection.select({ "include-controls" => [ { "with-ids" => %w[ksi-auth-02], "with-child-controls" => "yes" } ] }))
        .to eq(%w[ksi-auth-02 ksi-auth-02-a])
    end
  end

  describe "the backfill without stored parts" do
    it "classifies item rows by NIST's item ids, and leaves ac-20 out of ac-2" do
      catalog = create(:control_catalog)
      family = create(:control_family, control_catalog: catalog, code: "AC")
      %w[ac-1 ac-1a ac-1a.1 ac-2 ac-2.1 ac-20].each { |id| family.catalog_controls.create!(control_id: id, title: id) }

      CatalogHierarchyBackfill.new(catalog).run

      expect(rows(catalog)).to eq([
        [ "ac-1", nil, false ], [ "ac-1a", "ac-1", true ], [ "ac-1a.1", "ac-1", true ],
        [ "ac-2", nil, false ], [ "ac-2.1", "ac-2", false ], [ "ac-20", nil, false ]
      ])
    end
  end

  describe "the backfill from stored parts" do
    it "resolves a sub-item through its parent item whatever order the parts are stored in" do
      catalog = create(:control_catalog)
      family = create(:control_family, control_catalog: catalog, code: "CP")
      base = family.catalog_controls.create!(control_id: "cp-3", title: "Base")
      %w[cp-3.2 cp-3a cp-3a.2].each { |id| family.catalog_controls.create!(control_id: id, title: id) }
      # Child first: the sub-item "2." is stored before the item "a." it sits under.
      [ [ "cp-3_smt.a.2", "cp-3_smt.a", "item", "2." ], [ "cp-3_smt.a", "cp-3_smt", "item", "a." ],
        [ "cp-3_smt", nil, "statement", nil ] ].each do |pid, parent, name, label|
        CatalogControlPart.create!(catalog_control: base, part_id: pid, parent_part_id: parent, part_name: name,
                                   label: label, uuid: SecureRandom.uuid)
      end

      CatalogHierarchyBackfill.new(catalog).run

      expect(rows(catalog)).to eq([
        [ "cp-3", nil, false ], [ "cp-3.2", "cp-3", false ], [ "cp-3a", "cp-3", true ], [ "cp-3a.2", "cp-3", true ]
      ])
    end
  end

  describe "a control created by hand" do
    it "is placed under the nearest control its id extends" do
      catalog = create(:control_catalog)
      family = create(:control_family, control_catalog: catalog, code: "ZZ")
      family.catalog_controls.create!(control_id: "zz-2", title: "Base")
      enhancement = family.catalog_controls.build(control_id: "zz-2.3", title: "Enh").assign_inferred_parent
      separate = family.catalog_controls.build(control_id: "zz-20", title: "Other").assign_inferred_parent

      expect(enhancement.parent_control_id).to eq("zz-2")
      expect(separate.parent_control_id).to be_nil
    end

    it "is placed the same way when saved by any writer, with no call of its own" do
      catalog = create(:control_catalog)
      family = create(:control_family, control_catalog: catalog, code: "ZZ")
      family.catalog_controls.create!(control_id: "zz-2", title: "Base")

      expect(family.catalog_controls.create!(control_id: "zz-2.3", title: "Enh").parent_control_id).to eq("zz-2")
      expect(family.catalog_controls.create!(control_id: "zz-20", title: "Other").parent_control_id).to be_nil
    end

    it "is a statement item of the control when its id extends that control's by a letter" do
      catalog = create(:control_catalog)
      family = create(:control_family, control_catalog: catalog, code: "ZZ")
      family.catalog_controls.create!(control_id: "zz-2", title: "Base")

      item = family.catalog_controls.create!(control_id: "zz-2a", title: "Item")
      control = family.catalog_controls.create!(control_id: "zz-2.1", title: "Enh")

      expect([ item.statement_item, item.parent_control_id ]).to eq([ true, "zz-2" ])
      expect([ control.statement_item, control.parent_control_id ]).to eq([ false, "zz-2" ])
    end
  end

  describe "a catalog file that places a control at the top level" do
    it "keeps it there even when its id extends another control's" do
      flat = ksi_style.deep_dup
      flat["catalog"]["groups"].first["controls"] = [
        { "id" => "zz-2", "title" => "Invented base" }, { "id" => "zz-2.1", "title" => "Invented sibling" }
      ]
      catalog = import_json(flat)

      expect(rows(catalog)).to eq([ [ "zz-2", nil, false ], [ "zz-2.1", nil, false ] ])
    end
  end
end
