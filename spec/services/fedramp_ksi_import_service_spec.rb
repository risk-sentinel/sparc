# frozen_string_literal: true

require "rails_helper"
require "fileutils"

# #1115 / #1172 — the importer is proved against a catalog populated the OLD
# way (numbered ids, old themes, validations attached), not only against an
# empty database: re-keying real data is the part that can lose an assessment.
RSpec.describe FedrampKsiImportService do
  let(:legacy_map) { YAML.safe_load_file(Rails.root.join("lib/data/fedramp/ksi_legacy_map.yml")).fetch("indicators") }
  let(:boundary) { create(:authorization_boundary) }

  def ksi_catalog = ControlCatalog.find_by(source: "FedRAMP 20x")
  def control(id) = CatalogControl.joins(:control_family).find_by(control_families: { control_catalog_id: ksi_catalog.id }, control_id: id)

  # The catalog as db/seeds/fedramp_20x_ksi.rb built it before #1115: 11 themes,
  # the 54 numbered ids of the approved map.
  def seed_old_catalog!
    catalog = ControlCatalog.create!(name: "FedRAMP 20x Key Security Indicators", source: "FedRAMP 20x", version: "1.0.0")
    legacy_map.each do |old_id, row|
      code = old_id.split("-")[1].upcase
      fam = catalog.control_families.find_or_create_by!(code: code) { |f| f.name = "#{code} theme" }
      fam.catalog_controls.create!(control_id: old_id, label: old_id.upcase, sort_id: old_id, title: row["title"])
    end
    catalog
  end

  def validate!(id, status) = KsiValidation.create!(authorization_boundary: boundary, catalog_control: control(id), status: status)

  def rev5_catalog!(controls = %w[ac-2 ac-2.2 ia-12])
    catalog = ControlCatalog.create!(name: "Electronic (OSCAL) Version of NIST SP 800-53 Rev 5.2.0", source: "OSCAL",
                                     version: "5.2.0", framework: "NIST SP 800-53")
    controls.each do |id|
      fam = catalog.control_families.find_or_create_by!(code: id.split("-").first.upcase) { |f| f.name = id }
      fam.catalog_controls.create!(control_id: id, sort_id: id, title: id)
    end
    catalog
  end

  # A scratch copy of lib/data/fedramp, so a test can damage one file.
  def data_dir_with
    dir = Dir.mktmpdir("ksi-import-")
    FileUtils.cp(Dir[Rails.root.join("lib/data/fedramp/*")], dir)
    yield Pathname(dir)
    dir
  end

  describe "a fresh database" do
    it "builds the catalog FedRAMP publishes: 10 themes, 46 indicators, its version and digest" do
      result = described_class.new.call

      expect(result).to be_imported
      expect(ksi_catalog.version).to eq("2026.09.13.02")
      expect(ksi_catalog.control_families.not_retired.pluck(:code)).to match_array(%w[CED CMT CNA IAM INR MLA PIY RPL SCR SVC])
      current = CatalogControl.joins(:control_family).where(control_families: { control_catalog_id: ksi_catalog.id }).not_retired
      expect(current.count).to eq(46)
      expect(control("ksi-iam-elp").label).to eq("KSI-IAM-ELP")
    end

    it "is a no-op the second time — the same snapshot imports as unchanged" do
      described_class.new.call
      before = CatalogControl.maximum(:updated_at)

      expect(described_class.new.call).to be_unchanged
      expect(CatalogControl.maximum(:updated_at)).to eq(before)
    end

    it "gives an indicator with a per-class statement both classes" do
      described_class.new.call

      expect(control("ksi-cna-eis").description).to match(/\AClass B: .+\nClass C: /m)
    end
  end

  describe "re-keying a catalog populated the old way" do
    before { seed_old_catalog! }

    it "renames the ten approved indicators IN PLACE, so their validations move with them" do
      row_id = control("ksi-iam-02").id
      validation = validate!("ksi-iam-02", "passed")

      expect(described_class.new.call).to be_imported

      renamed = control("ksi-iam-elp")
      expect(renamed.id).to eq(row_id)
      expect(validation.reload.catalog_control_id).to eq(row_id)
      expect(validation.status).to eq("passed")
      expect(renamed).not_to be_retired
    end

    it "retires every other old indicator and keeps its validation — nothing is deleted" do
      validation = validate!("ksi-edu-01", "not_assessed")
      auth = validate!("ksi-auth-01", "passed")
      before = CatalogControl.count

      described_class.new.call

      old = CatalogControl.find(validation.catalog_control_id)
      expect(old).to be_retired
      expect(old.superseded_by).to eq(legacy_map.dig("ksi-edu-01", "superseded_by"))
      expect(auth.reload.status).to eq("passed")
      expect(KsiValidation.count).to eq(2)
      expect(CatalogControl.count).to eq(before + 36) # 46 current - 10 renamed in place
    end

    it "renames themes in place and retires AUTH, which FedRAMP no longer has" do
      edu = ksi_catalog.control_families.find_by(code: "EDU").id

      described_class.new.call

      expect(ksi_catalog.control_families.find_by(code: "CED").id).to eq(edu)
      expect(ksi_catalog.control_families.find_by(code: "AUTH")).to be_retired
    end

    it "moves a renamed indicator into its new theme (svc-06 -> CNA)" do
      described_class.new.call

      expect(control("ksi-cna-rnt").control_family.code).to eq("CNA")
    end
  end

  describe "a later FedRAMP release" do
    it "retires an indicator the new snapshot no longer publishes, keeping its validation, with no successor claimed" do
      described_class.new.call
      validation = validate!("ksi-iam-jit", "passed")
      dir = data_dir_with do |d|
        rules = JSON.parse(d.join("fedramp-consolidated-rules.json").read)
        rules["KSI"]["IAM"]["indicators"].delete("KSI-IAM-JIT")
        rules["info"]["version"] = "2026.10.01.01"
        d.join("fedramp-consolidated-rules.json").write(JSON.pretty_generate(rules))
      end

      result = described_class.new(data_dir: dir).call

      expect(result).to be_imported
      jit = CatalogControl.find(validation.catalog_control_id)
      expect(jit).to be_retired
      expect(jit.superseded_by).to eq([])
      expect(validation.reload.status).to eq("passed")
      expect(ksi_catalog.reload.version).to eq("2026.10.01.01")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  describe "the crosswalk" do
    it "is rebuilt from FedRAMP's controls[] against the Rev 5 catalog found by framework, not by name" do
      rev5 = rev5_catalog!

      result = described_class.new.call

      mapping = ControlMapping.find_by(name: described_class::MAPPING_NAME)
      expect(mapping.target_catalog).to eq(rev5)
      targets = mapping.control_mapping_entries.where(source_control_id: "ksi-iam-aam").pluck(:target_control_id)
      expect(targets).to include("ac-2.2", "ia-12")
      expect(result.changes[:crosswalk_targets_not_in_rev5]).to be > 0
    end

    it "is built on the next import when Rev 5 arrives after the KSI catalog — an unchanged snapshot is not enough" do
      described_class.new.call
      rev5_catalog!

      expect(described_class.new.call).to be_imported
      expect(ControlMapping.find_by(name: described_class::MAPPING_NAME).control_mapping_entries).to exist
    end

    it "is skipped, and says so, when no Rev 5 catalog is loaded" do
      expect(described_class.new.call.changes[:crosswalk]).to match(/skipped/)
    end
  end

  describe "refusal — nothing is written" do
    it "refuses data that does not validate against FedRAMP's schema" do
      dir = data_dir_with { |d| d.join("fedramp-consolidated-rules.json").write({ "info" => {} }.to_json) }

      result = described_class.new(data_dir: dir).call

      expect(result).to be_refused
      expect(ksi_catalog).to be_nil
    ensure
      FileUtils.rm_rf(dir) if dir
    end

    it "refuses a map that renames onto an id FedRAMP does not publish, rolling back everything" do
      seed_old_catalog!
      dir = data_dir_with do |d|
        map = YAML.safe_load_file(d.join("ksi_legacy_map.yml"))
        map["indicators"]["ksi-iam-02"]["rename_to"] = "KSI-IAM-XYZ"
        d.join("ksi_legacy_map.yml").write(map.to_yaml)
      end

      result = described_class.new(data_dir: dir).call

      expect(result).to be_refused
      expect(result.errors.join).to match(/KSI-IAM-XYZ is not in FedRAMP/)
      expect(ksi_catalog.version).to eq("1.0.0")
      expect(control("ksi-iam-02")).to be_present
    ensure
      FileUtils.rm_rf(dir) if dir
    end

    it "records the refusal" do
      dir = data_dir_with { |d| d.join("fedramp-consolidated-rules.json").write({ "info" => {} }.to_json) }

      expect { described_class.new(data_dir: dir).call }
        .to change { AuditEvent.where(action: "ksi_catalog_import_refused").count }.by(1)
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "dry run reports the import, then rolls every change back" do
    seed_old_catalog!

    result = described_class.new(dry_run: true).call

    expect(result).to be_planned
    expect(result.changes[:renamed]).to eq(10)
    expect(ksi_catalog.version).to eq("1.0.0")
    expect(control("ksi-iam-02")).to be_present
  end
end
