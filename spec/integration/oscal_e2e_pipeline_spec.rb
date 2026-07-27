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

  # ── Stage 3 — baselines selected FROM the stage 1 catalog ────────────────
  #
  # These are the NIST SP 800-53 rev5 Low/Moderate/High baselines, which ship
  # as fixtures. They are NOT FedRAMP's baselines: FedRAMP's rev5 profiles live
  # in GSA/fedramp-automation, which returns 404 (checked authenticated and
  # anonymous, both orgs), so they cannot be committed as fixtures. Calling a
  # NIST baseline "FedRAMP" would be a lie about this spec's own coverage — see
  # decision D1 in docs/dev/817_oscal_e2e_design.md.
  describe "Stage 3 — baselines and profile resolution" do
    BASELINES = {
      "LOW" => "NIST_SP-800-53_rev5_LOW-baseline_profile.json",
      "MODERATE" => "NIST_SP-800-53_rev5_MODERATE-baseline_profile.json",
      "HIGH" => "NIST_SP-800-53_rev5_HIGH-baseline_profile.json"
    }.freeze

    # Control ids the fixture baseline selects, straight from the OSCAL profile.
    def baseline_control_ids(filename)
      data = JSON.parse(Rails.root.join("spec/fixtures/files/profiles", filename).read)
      data.dig("profile", "imports")
          .flat_map { |i| i["include-controls"] || [] }
          .flat_map { |i| i["with-ids"] || [] }
    end

    def build_baseline(level)
      profile = create(:profile_document, name: "NIST rev5 #{level}", baseline_level: level,
                                          control_catalog: catalog)
      ProfileControlSelectionService.new(profile).update(baseline_control_ids(BASELINES.fetch(level)))
      profile.reload
    end

    it "selects each baseline's controls out of the imported catalog" do
      BASELINES.each_key do |level|
        profile = build_baseline(level)
        requested = baseline_control_ids(BASELINES.fetch(level))

        # Selection resolves against the catalog, so a control the baseline
        # names but the catalog lacks is silently dropped. Assert the overlap
        # is total — a partial selection is a broken seam between stages 1 and 3.
        missing = requested - profile.profile_controls.pluck(:control_id)
        expect(missing).to be_empty,
          "#{level}: #{missing.size} baseline controls absent from the catalog — #{missing.first(5).inspect}"
      end
    end

    it "produces cumulative baselines — LOW ⊂ MODERATE ⊂ HIGH" do
      # A genuine property of the 800-53 baselines, and a strong signal that
      # selection is driven by the profile rather than by chance: each level
      # must be a strict superset of the one below it.
      low = baseline_control_ids(BASELINES["LOW"]).to_set
      moderate = baseline_control_ids(BASELINES["MODERATE"]).to_set
      high = baseline_control_ids(BASELINES["HIGH"]).to_set

      expect(low).to be < moderate, "LOW is not a strict subset of MODERATE"
      expect(moderate).to be < high, "MODERATE is not a strict subset of HIGH"
      expect([ low.size, moderate.size, high.size ]).to eq([ 149, 287, 370 ])
    end

    it "exports each baseline as a schema-valid OSCAL profile (JSON + YAML)" do
      BASELINES.each_key do |level|
        profile = build_baseline(level)
        json = OscalProfileExportService.new(profile).export

        expect_valid_json_and_yaml(json, model_type: :profile, label: "Stage 3 #{level} profile")
      end
    end

    it "resolves each baseline into a schema-valid OSCAL catalog" do
      # Profile resolution is the seam that matters most here: the resolved
      # output is a CATALOG, so it must satisfy the catalog schema, not the
      # profile schema it came from.
      BASELINES.each_key do |level|
        profile = build_baseline(level)
        json = OscalResolvedProfileCatalogService.new(profile).export

        expect_valid_json_and_yaml(json, model_type: :catalog, label: "Stage 3 #{level} resolved")
      end
    end

    it "carries every selected control into the resolved catalog" do
      profile = build_baseline("LOW")
      selected = profile.profile_controls.pluck(:control_id).to_set

      data = JSON.parse(OscalResolvedProfileCatalogService.new(profile).export)
      resolved = (data.dig("catalog", "groups") || [])
                 .flat_map { |g| g["controls"] || [] }
                 .map { |c| c["id"] }.to_set

      expect(selected - resolved).to be_empty,
        "resolution dropped #{(selected - resolved).size} controls the profile selected"
    end

    it "REJECTS a profile with no import — a baseline that selects nothing" do
      profile = create(:profile_document, name: "empty", baseline_level: "LOW",
                                          control_catalog: catalog)
      json = OscalProfileExportService.new(profile).export_unvalidated

      expect_rejected_by_schema(json, model_type: :profile, label: "Stage 3 empty profile") do |data|
        data["profile"]["imports"] = []
      end
    end
  end

  # ── Stage 2 — SPARC organization-defined parameters ──────────────────────
  #
  # Sequenced after stage 3 in the file because ODPs are applied TO a baseline,
  # so the baseline has to exist first. The pipeline order is unchanged.
  describe "Stage 2 — organization-defined parameters" do
    let(:profile) do
      p = create(:profile_document, name: "ODP target", baseline_level: "LOW",
                                    control_catalog: catalog)
      ids = JSON.parse(Rails.root.join(
        "spec/fixtures/files/profiles/NIST_SP-800-53_rev5_LOW-baseline_profile.json"
      ).read).dig("profile", "imports").flat_map { |i| i["include-controls"] || [] }
        .flat_map { |i| i["with-ids"] || [] }
      ProfileControlSelectionService.new(p).update(ids)
      p.reload
    end

    # #817 requires the ODP importer exercised on every format it accepts.
    # The three fixtures carry the SAME parameters, so a per-format difference
    # can only be a parser fault.
    %w[json yaml xml].each do |format|
      it "imports organization-defined parameters from #{format.upcase}" do
        content = Rails.root.join("spec/fixtures/files/odp/sample_odp.#{format}").read
        payload = OdpImportService.parse(content: content, format: format)

        expect(payload[:parameters]).to be_present,
          "#{format}: parsed no parameters out of the ODP fixture"

        result = OdpImportService.new(profile).apply(payload)
        expect(result).to be_present
      end
    end

    it "previews without writing, so an operator sees the diff first" do
      content = Rails.root.join("spec/fixtures/files/odp/sample_odp.json").read
      payload = OdpImportService.parse(content: content, format: "json")

      fields = -> { ProfileControlField.where(profile_control_id: profile.profile_controls.select(:id))
                                       .order(:id).pluck(:id, :field_value) }
      before_values = fields.call
      preview = OdpImportService.new(profile).preview(payload)

      expect(preview[:rows]).to be_present
      expect(preview[:stats]).to include(:total)
      expect(fields.call).to eq(before_values),
        "preview wrote to the database — it must be non-destructive"
    end

    it "REJECTS an unsupported ODP format" do
      expect {
        OdpImportService.parse(content: "irrelevant", format: "docx")
      }.to raise_error(OdpImportService::ImportError, /Unsupported format/)
    end

    it "REJECTS an empty ODP file" do
      expect {
        OdpImportService.parse(content: "   ", format: "json")
      }.to raise_error(OdpImportService::ImportError, /Empty file/)
    end

    it "REJECTS malformed JSON rather than importing nothing silently" do
      expect {
        OdpImportService.parse(content: "{not json", format: "json")
      }.to raise_error(OdpImportService::ImportError)
    end
  end
end
