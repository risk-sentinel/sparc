# frozen_string_literal: true

require "rails_helper"

# #1252 — the new selection rules leave every NIST baseline selecting exactly
# what it did: each lists its controls by `with-ids`, so the selection is the
# ids in the order listed. The expectation is read from each file, not pinned.
RSpec.describe "NIST baseline selection is unchanged (#1252)" do
  let(:dir) { Rails.root.join("spec/fixtures/files") }

  before(:all) do
    name = "NIST_SP-800-53_rev5_catalog.json"
    @catalog = CatalogImportService.call(File.open(Rails.root.join("spec/fixtures/files/catalogs", name)), name)[:catalog]
  end

  after(:all) { @catalog&.destroy }

  %w[
    NIST_SP-800-53_rev5_LOW-baseline_profile.json
    NIST_SP-800-53_rev5_MODERATE-baseline_profile.json
    NIST_SP-800-53_rev5_HIGH-baseline_profile.json
    NIST_SP-800-53_rev5_MODERATE-tailored_profile.json
  ].each do |name|
    it "#{name} selects its with-ids, in the order listed" do
      path = dir.join("profiles", name)
      listed = JSON.parse(File.read(path)).dig("profile", "imports")
                   .flat_map { |imp| Array(imp["include-controls"]).flat_map { |ic| Array(ic["with-ids"]) } }.uniq

      doc = create(:profile_document, status: "processing", file_type: "json", original_filename: name, control_catalog: nil)
      ProfileJsonParserService.new(doc, path.to_s).parse

      expect(doc.reload.profile_controls.order(:row_order).pluck(:control_id)).to eq(listed)
      # Every id a linked baseline names is a control in NIST's catalog. (The
      # HIGH fixture's import href names a back-matter resource the file does
      # not contain, so it links no catalog, as it never has.)
      Array(doc.import_metadata["imports"]).select { |imp| imp["catalog_id"] }.each do |imp|
        expect(imp["catalog_id"]).to eq(@catalog.id)
        expect(imp).not_to have_key("unknown_ids")
      end
    end
  end
end
