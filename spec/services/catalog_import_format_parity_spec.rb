# frozen_string_literal: true

require "rails_helper"

# #1228 / #1241 — a catalog imports to the same rows whatever its format.
#
# The XML import used to read the file with its own reduced model: it dropped a
# param's `<value>`, flattened guideline prose to plain text, kept no
# assessment data and stored no parts. JSON, YAML and XML now share one import
# path (XML and YAML are converted to the JSON model first), and these examples
# hold them to one result: identical parts, `guidance_data` and `params_data`,
# `values` included.
RSpec.describe "catalog import: JSON, YAML and XML agree" do
  # Each format is imported inside a savepoint and rolled back, so the three
  # imports cannot see each other's rows: a row one format failed to write can
  # not be supplied by another.
  def snapshot(path)
    snap = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      catalog = File.open(path) { |io| CatalogImportService.call(io, File.basename(path)) }[:catalog]
      snap = catalog_snapshot(catalog)
      raise ActiveRecord::Rollback
    end
    snap
  end

  def catalog_snapshot(catalog)
    controls = CatalogControl.joins(:control_family)
                             .where(control_families: { control_catalog_id: catalog.id })
                             .includes(:catalog_control_parts)
    controls.to_h do |control|
      parts = control.catalog_control_parts.sort_by(&:row_order).map do |part|
        part.attributes.slice("part_id", "part_name", "label", "parent_part_id", "prose", "props_data", "row_order")
      end
      [ control.control_id,
        { "title" => control.title, "label" => control.label, "sort_id" => control.sort_id,
          "guidance_data" => control.guidance_data, "params_data" => control.params_data,
          "links_data" => control.links_data, "parts" => parts } ]
    end
  end

  let(:dir) { Rails.root.join("spec/fixtures/files/catalogs") }

  context "an invented catalog whose params carry values" do
    let(:by_format) { %w[json yaml xml].to_h { |ext| [ ext, snapshot(dir.join("invented-values-catalog.#{ext}")) ] } }

    it "imports identical controls, parts, guidance and params from all three" do
      expect(by_format["json"]).to be_present
      expect(by_format["yaml"]).to eq(by_format["json"])
      expect(by_format["xml"]).to eq(by_format["json"])
    end

    it "keeps every param's `values` in every format (#1241)" do
      by_format.each do |format, snap|
        params = snap.dig("ex-1", "params_data").index_by { |p| p["id"] }

        expect(params.dig("ex-01_odp.01", "values")).to eq([ "Example Agency personnel" ]), format
        expect(params.dig("ex-01_odp.02", "values")).to eq([ "quarterly-invented" ]), format
        expect(params["ex-01_odp.04"]).not_to have_key("values")
      end
    end

    it "stores the parts tree from XML too, which the old XML import never did" do
      part_ids = by_format["xml"].dig("ex-1", "parts").map { |p| p["part_id"] }

      expect(part_ids).to include("ex-1_smt", "ex-1_smt.a", "ex-1_gdn", "ex-1_obj.a", "ex-1_asm-examine")
    end
  end

  context "NIST SP 800-53 Rev 5 v5.2.0, as NIST published it in each format" do
    it "imports identical controls, parts, guidance and params from all three" do
      json = snapshot(dir.join("NIST_SP-800-53_rev5_catalog.json"))
      xml  = snapshot(dir.join("NIST_SP-800-53_rev5_catalog.xml"))
      yaml = snapshot(dir.join("NIST_SP-800-53_rev5_catalog.yaml"))

      expect(json.size).to be > 2000
      expect(xml).to eq(json)
      expect(yaml).to eq(json)
    end
  end

  describe "the XML import" do
    it "records the format it came from" do
      result = File.open(dir.join("invented-values-catalog.xml")) { |io| CatalogImportService.call(io, "invented.xml") }

      expect(result[:catalog].metadata_extra["import_format"]).to eq("oscal_xml")
    end

    it "digests the ORIGINAL file, not the JSON it was converted to" do
      path = dir.join("invented-values-catalog.xml")
      result = File.open(path) { |io| CatalogImportService.call(io, "invented.xml") }

      expect(result[:catalog].catalog_content_digest).to eq(Digest::SHA256.hexdigest(path.binread))
    end

    it "refuses an XML catalog that is not schema-valid, before writing anything" do
      xml = dir.join("invented-values-catalog.xml").read.sub("<title>Example Policy</title>", "")

      expect {
        expect { CatalogImportService.call(StringIO.new(xml), "invalid.xml") }
          .to raise_error(CatalogImportService::ImportError, /Not a valid OSCAL XML catalog/)
      }.not_to change(CatalogControl, :count)
    end
  end
end
