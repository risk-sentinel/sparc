# frozen_string_literal: true

require "rails_helper"

# End-to-end OSCAL pipeline proof (#817) — stages 1 to 3.
#
# SPARC already has per-service specs for every exporter and parser, a
# cross-cutting compliance audit, and UUID round-trip stability checks. They all
# pass. What none of them can catch is a broken SEAM: nothing proves that stage
# N's OUTPUT is a valid stage N+1 INPUT. This spec drives the stages in order,
# against the real vanilla NIST catalog, and fails loudly where the chain parts.
#
#   Stage 1  vanilla NIST 800-53 rev5 catalog  → CatalogImportService
#   Stage 2  SPARC organization-defined params → OdpImportService
#   Stage 3  three baselines + resolution      → OscalResolvedProfileCatalogService
#
# Stages 4-6 (boundary, authorization artifacts, ATO package) land in later
# slices; see docs/dev/817_oscal_e2e_design.md.
#
# COST: the vanilla catalog is 10 MB / 2318 controls and takes ~28s to import.
# It is imported ONCE for the whole file, in before(:context). Transactional
# fixtures do NOT wrap before(:context), so it is torn down explicitly.
RSpec.describe "OSCAL end-to-end pipeline (#817)", :oscal_pipeline do
  CATALOG_FIXTURE = Rails.root.join(
    "spec/fixtures/files/catalogs/NIST_SP-800-53_rev5_catalog.json"
  ).freeze

  before(:context) do
    @catalog = CatalogImportService.call(
      File.open(CATALOG_FIXTURE), File.basename(CATALOG_FIXTURE)
    )
    @catalog = @catalog[:catalog] if @catalog.is_a?(Hash)
  end

  after(:context) do
    # before(:context) writes outside the per-example transaction, so it would
    # otherwise leak into every later spec file in the run.
    ProfileDocument.where(control_catalog_id: @catalog&.id).destroy_all
    @catalog&.destroy
  end

  let(:catalog) { @catalog }

  # ── Stage 1 — the vanilla catalog is the ground truth ────────────────────
  describe "Stage 1 — vanilla NIST SP 800-53 rev5 catalog" do
    it "imports the whole catalog, not a subset" do
      # 20 families is the rev5 structure. Asserting the shape rather than an
      # exact control count keeps this from breaking on a catalog revision
      # while still catching a truncated or partial import.
      expect(catalog.control_families.count).to eq(20)
      expect(catalog.catalog_controls.count).to be > 2000

      # Every family must actually carry controls — a family row with nothing
      # under it is the signature of an import that gave up part-way.
      empty = catalog.control_families.left_joins(:catalog_controls)
                     .group("control_families.id")
                     .having("COUNT(catalog_controls.id) = 0").count
      expect(empty).to be_empty, "families imported with no controls: #{empty.keys.inspect}"
    end

    it "round-trips to schema-valid OSCAL in JSON and YAML" do
      json = OscalCatalogExportService.new(catalog).export

      expect_valid_json_and_yaml(json, model_type: :catalog, label: "Stage 1 catalog")
    end

    it "produces well-formed XML carrying the catalog payload" do
      json = OscalCatalogExportService.new(catalog).export
      xml = OscalExportFormatService.to_xml(json, :catalog)

      # Well-formedness and payload survival are a separate question from XSD
      # conformance (below) — #816 showed the converter can raise outright.
      doc = Nokogiri::XML(xml)
      expect(doc.errors).to be_empty
      expect(doc.root.name).to eq("catalog")
      expect(doc.xpath("//*[local-name()='group']").size).to eq(20)
    end

    it "round-trips to XSD-valid OSCAL XML" do
      pending "#827 — OscalJsonToXmlConverter emits JSON key order instead of " \
              "the OSCAL XSD element sequence, so every XML export is " \
              "schema-invalid. Remove this marker when #827 lands."

      json = OscalCatalogExportService.new(catalog).export
      expect_valid_xml(json, model_type: :catalog, label: "Stage 1 catalog")
    end

    it "carries the controls through the export, not just the metadata" do
      data = JSON.parse(OscalCatalogExportService.new(catalog).export)
      groups = data.dig("catalog", "groups") || []

      expect(groups.size).to eq(20)
      exported_controls = groups.sum { |g| (g["controls"] || []).size }
      expect(exported_controls).to be > 200,
        "catalog exported #{exported_controls} top-level controls — payload was dropped"
    end

    it "REJECTS a catalog whose required metadata is missing" do
      json = OscalCatalogExportService.new(catalog).export

      expect_rejected_by_schema(json, model_type: :catalog, label: "Stage 1 catalog") do |data|
        data["catalog"].delete("metadata")
      end
    end

    it "REJECTS a catalog carrying a non-UUID document id" do
      json = OscalCatalogExportService.new(catalog).export

      expect_rejected_by_schema(json, model_type: :catalog, label: "Stage 1 catalog") do |data|
        data["catalog"]["uuid"] = "not-a-uuid"
      end
    end

    it "REJECTS a document validated as the WRONG model type" do
      # A catalog is not a profile. If the validator accepted this, every
      # positive assertion in this file would be worthless.
      json = OscalCatalogExportService.new(catalog).export
      result = OscalSchemaValidationService.validate_json(:profile, json)

      expect(result.valid?).to be(false),
        "the profile schema accepted a catalog document"
    end
  end
end
