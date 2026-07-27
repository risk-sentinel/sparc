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

  # ── Stage 4 — the authorization boundary, from the full ECS CDEF set ─────
  #
  # These are the 19 real ECS Fargate component definitions from sparc-iac,
  # sanitized into spec/fixtures/files/components/ecs_boundary/ by
  # scripts/sanitize_ecs_cdefs.rb. Using the real set matters: hand-built
  # minimal CDEFs pass trivially and taught us nothing in #816.
  #
  # Every import here runs with `validate: true` — the path a customer upload
  # takes. The trusted-pipeline `validate: false` escape hatch exists for AWS
  # Labs ingest and is deliberately NOT used, because a CDEF that only imports
  # unvalidated is a CDEF a customer cannot upload.
  describe "Stage 4 — authorization boundary from the ECS Fargate CDEF set" do
    ECS_CDEF_DIR = Rails.root.join("spec/fixtures/files/components/ecs_boundary").freeze

    def ecs_cdef_paths
      Dir.glob(ECS_CDEF_DIR.join("component-definition-*.json")).sort
    end

    def import_cdef(path)
      doc = create(:cdef_document, name: File.basename(path, ".json"),
                                   file_type: "json", original_filename: File.basename(path))
      CdefJsonParserService.new(doc, path).parse(validate: true)
      doc.reload
    end

    it "ships the whole ECS boundary, not a sample of it" do
      expect(ecs_cdef_paths.size).to eq(19)
    end

    it "imports every ECS component definition through the validating path" do
      failures = []
      ecs_cdef_paths.each do |path|
        import_cdef(path)
      rescue StandardError => e
        failures << "#{File.basename(path)}: #{e.class} — #{e.message}"
      end

      expect(failures).to be_empty,
        "ECS CDEFs a customer could not upload:\n  #{failures.join("\n  ")}"
    end

    it "imports controls, not just document shells" do
      empty = []
      ecs_cdef_paths.each do |path|
        doc = import_cdef(path)
        empty << File.basename(path) if doc.cdef_controls.empty?
      end

      expect(empty).to be_empty,
        "component definitions that imported with zero controls: #{empty.inspect}"
    end

    it "assembles the full set into one authorization boundary" do
      ab = create(:authorization_boundary)
      boundary = create(:boundary, authorization_boundary: ab)

      ecs_cdef_paths.each do |path|
        BoundaryCdefDocument.create!(boundary: boundary, cdef_document: import_cdef(path))
      end

      # cdef_documents reaches through Boundary, so this also proves the
      # AuthorizationBoundary → Boundary → CdefDocument chain is wired.
      expect(ab.cdef_documents.distinct.count).to eq(19)
    end

    it "exports an imported ECS component definition as valid OSCAL (JSON + YAML)" do
      doc = import_cdef(ecs_cdef_paths.first)
      json = OscalComponentDefinitionExportService.new(doc).export

      expect_valid_json_and_yaml(json, model_type: :component_definition,
                                       label: "Stage 4 #{doc.name}")
    end

    it "REJECTS a component definition whose required metadata is missing" do
      doc = import_cdef(ecs_cdef_paths.first)
      json = OscalComponentDefinitionExportService.new(doc).export

      expect_rejected_by_schema(json, model_type: :component_definition,
                                      label: "Stage 4 #{doc.name}") do |data|
        data["component-definition"].delete("metadata")
      end
    end

    # #817's import matrix: CDEFs must be ingestible from JSON, YAML, XML and
    # XCCDF. JSON is covered above by the whole ECS set; these cover the rest.
    describe "the import matrix" do
      it "imports a component definition from YAML" do
        path = Rails.root.join("spec/fixtures/files/components/example-component-definition.yaml").to_s
        doc = create(:cdef_document, file_type: "yaml", original_filename: File.basename(path))

        CdefYamlParserService.new(doc, path).parse(validate: true)

        expect(doc.reload.cdef_controls).to be_present
      end

      it "imports a component definition from OSCAL XML" do
        path = Rails.root.join("spec/fixtures/files/components/example-component-definition.xml").to_s
        doc = create(:cdef_document, file_type: "xml", original_filename: File.basename(path))

        CdefXccdfParserService.new(doc, path).parse(validate: true)

        expect(doc.reload.cdef_controls).to be_present
      end

      it "imports a STIG from XCCDF" do
        path = Rails.root.join("spec/fixtures/files/components/test-stig-xccdf.xml").to_s
        doc = create(:cdef_document, file_type: "xccdf", cdef_type: "disa_stig",
                                     original_filename: File.basename(path))

        CdefXccdfParserService.new(doc, path).parse(validate: true)

        expect(doc.reload.cdef_controls).to be_present
      end

      it "REJECTS a file whose content does not match its declared format" do
        # A JSON catalog handed to the XML parser must fail deliberately, not
        # import as an empty shell — a silent no-op reads as a successful
        # upload to the operator.
        path = Rails.root.join("spec/fixtures/files/catalogs/basic-catalog.yaml").to_s
        doc = create(:cdef_document, file_type: "xml", original_filename: "basic-catalog.yaml")

        imported_controls = begin
          CdefXccdfParserService.new(doc, path).parse(validate: true)
          doc.reload.cdef_controls.count
        rescue StandardError
          :raised
        end

        expect(imported_controls).to satisfy { |r| r == :raised || r.zero? },
          "a YAML catalog was imported as an XML component definition"
      end
    end
  end

  # ── Stage 5 — the authorization artifacts ────────────────────────────────
  #
  # SSP, SAP, SAR and POA&M, generated FROM the stage 3 baseline rather than
  # built by hand. That is the point: each generator consumes the previous
  # stage's output, so these examples cover seams no per-service spec can.
  describe "Stage 5 — authorization artifacts" do
    # SspFromProfileService and SarFromProfileService refuse a profile that is
    # unpublished OR unresolved — you cannot build an authorization artifact
    # from a draft baseline, or from one whose controls have never been
    # resolved against the catalog.
    #
    # This mirrors ProfileDocumentsController#before_publish_lifecycle, which
    # runs OscalResolvedProfileCatalogService and stores the result on publish.
    # Reproducing the real publish behaviour is the point: stage 3's RESOLUTION
    # output is stage 5's input, and that is the seam under test.
    let(:baseline) do
      profile = create(:profile_document, name: "Stage 5 baseline", baseline_level: "LOW",
                                          control_catalog: catalog)
      ids = JSON.parse(Rails.root.join(
        "spec/fixtures/files/profiles/NIST_SP-800-53_rev5_LOW-baseline_profile.json"
      ).read).dig("profile", "imports").flat_map { |i| i["include-controls"] || [] }
        .flat_map { |i| i["with-ids"] || [] }
      ProfileControlSelectionService.new(profile).update(ids)

      resolved = OscalResolvedProfileCatalogService.new(profile.reload).export
      profile.update!(resolved_catalog_json: JSON.parse(resolved), lifecycle_status: "published")
      profile.reload
    end

    # A POA&M with authored content OSCAL actually requires. #816 established
    # that a missing risk/statement or finding/target is fixed in the DATA,
    # never with an exporter fallback — a synthesised statement yields a
    # schema-valid POA&M that misrepresents the risk, which is worse than a
    # failed export. Mirrors db/seeds/sample_artifacts.rb.
    def authored_poam
      poam = create(:poam_document, authorization_boundary: create(:authorization_boundary))
      item = PoamItem.create!(
        poam_document: poam, title: "Incident response plan not tested in 12 months",
        description: "The IR plan has not been exercised within the past year.",
        poam_item_uuid: SecureRandom.uuid, risk_status: "remediating",
        impact: "medium", likelihood: "low", row_order: 0
      )
      risk = PoamRisk.create!(
        poam_document: poam, title: "Risk: untested incident response plan",
        uuid: SecureRandom.uuid,
        description: "Risk associated with an untested incident response plan.",
        statement: "An untested incident response plan is unproven under load: response times, " \
                   "escalation paths and contact accuracy remain unverified, so the organization " \
                   "cannot demonstrate it can contain an incident within its stated objectives.",
        status: "remediating", likelihood: "low", impact: "medium",
        # A POA&M is a time commitment, so a risk without a deadline is an
        # incomplete one. hdf-cli 3.4.1 enforces this: 3.3.2 silently invented
        # "conversion time + 1 year", 3.4.1 fails loud instead (#764). The
        # deadline is authored here for the same reason risk/statement is —
        # it is substantive content, not something a tool should invent.
        deadline: Time.zone.parse("2026-10-01T00:00:00Z")
      )
      finding = PoamFinding.create!(
        poam_document: poam, title: "Finding: IR exercise overdue",
        uuid: SecureRandom.uuid,
        description: "Last IR exercise was conducted 18 months ago.",
        target_data: {
          "type" => "statement-id", "target-id" => "ir-3_smt",
          "title" => "Assessment objective for IR-3",
          "description" => "Last IR exercise was conducted 18 months ago.",
          "status" => { "state" => "not-satisfied" }
        }
      )
      PoamItemRisk.create!(poam_item: item, poam_risk: risk)
      PoamItemFinding.create!(poam_item: item, poam_finding: finding)
      poam.reload
    end

    describe "SSP" do
      it "is generated from the baseline and carries its controls" do
        ssp = SspFromProfileService.new(baseline, name: "ECS Fargate SSP").create

        expect(ssp).to be_persisted
        selected = baseline.profile_controls.pluck(:control_id).to_set
        carried = ssp.ssp_controls.pluck(:control_id).to_set

        expect(selected - carried).to be_empty,
          "SSP generation dropped #{(selected - carried).size} controls the baseline selected"
      end

      it "exports as a schema-valid OSCAL system-security-plan (JSON + YAML)" do
        ssp = SspFromProfileService.new(baseline, name: "ECS Fargate SSP").create
        json = OscalSspExportService.new(ssp).export

        expect_valid_json_and_yaml(json, model_type: :ssp, label: "Stage 5 SSP")
      end

      it "REJECTS an SSP missing its system-characteristics" do
        ssp = SspFromProfileService.new(baseline, name: "ECS Fargate SSP").create
        json = OscalSspExportService.new(ssp).export

        expect_rejected_by_schema(json, model_type: :ssp, label: "Stage 5 SSP") do |data|
          data["system-security-plan"].delete("system-characteristics")
        end
      end
    end

    describe "SAP" do
      it "is generated from the SSP and exports as a valid assessment-plan" do
        ssp = SspFromProfileService.new(baseline, name: "ECS Fargate SSP").create
        sap = SapGeneratorService.new(name: "ECS Fargate SAP", ssp_document: ssp).generate

        expect(sap).to be_persisted
        json = OscalAssessmentPlanExportService.new(sap).export
        expect_valid_json_and_yaml(json, model_type: :assessment_plan, label: "Stage 5 SAP")
      end

      it "REJECTS an assessment-plan with no import-ssp" do
        ssp = SspFromProfileService.new(baseline, name: "ECS Fargate SSP").create
        sap = SapGeneratorService.new(name: "ECS Fargate SAP", ssp_document: ssp).generate
        json = OscalAssessmentPlanExportService.new(sap).export

        expect_rejected_by_schema(json, model_type: :assessment_plan, label: "Stage 5 SAP") do |data|
          data["assessment-plan"].delete("import-ssp")
        end
      end
    end

    describe "SAR" do
      it "is generated from the baseline and exports as valid assessment-results" do
        sar = SarFromProfileService.new(baseline, name: "ECS Fargate SAR").create

        expect(sar).to be_persisted
        json = OscalSarExportService.new(sar).export
        expect_valid_json_and_yaml(json, model_type: :assessment_results, label: "Stage 5 SAR")
      end

      it "REJECTS assessment-results with no results" do
        sar = SarFromProfileService.new(baseline, name: "ECS Fargate SAR").create
        json = OscalSarExportService.new(sar).export

        expect_rejected_by_schema(json, model_type: :assessment_results, label: "Stage 5 SAR") do |data|
          data["assessment-results"]["results"] = []
        end
      end
    end

    # ── HDF ingestion — the assessment side of the import matrix ──────────
    #
    # This runs the REAL hdf-cli (3.4.1, baked into the image), not a stubbed
    # runner. Stubbing it would prove only that our wrapper calls a method;
    # the question #817 asks is whether scan output actually becomes valid
    # OSCAL, and that lives in the converter we do not own.
    describe "HDF scan results" do
      let(:hdf_fixture) { Rails.root.join("spec/fixtures/files/hdf/sample-results.hdf.json").to_s }

      it "converts HDF results into an OSCAL assessment-results document" do
        oscal = HdfOscalTranslationService.new.hdf_to_oscal_sar(hdf_fixture)

        # The conversion itself works and produces the right document shape;
        # what it produces is not schema-valid (see below).
        expect(oscal).to have_key("assessment-results")
        expect(oscal.dig("assessment-results", "results")).to be_present
      end

      it "converts to SCHEMA-VALID OSCAL assessment-results" do
        pending "#831 — hdf-cli 3.4.1 emits assessment-results missing required " \
                "properties (reviewed-controls, finding/description, " \
                "characterization/origin) and SPARC returns it unvalidated from " \
                "/api/v1/translations. Remove this marker when #831 lands."

        oscal = HdfOscalTranslationService.new.hdf_to_oscal_sar(hdf_fixture)
        expect_valid_json_and_yaml(JSON.generate(oscal), model_type: :assessment_results,
                                                         label: "Stage 5 HDF -> SAR")
      end

      # OSCAL POA&M is sourced from HDF **Amendments**, not from raw HDF: the
      # direct hdf -> oscal-poam converter was removed in 3.2.0 by design
      # (mitre/hdf-libs#104). These two examples pin BOTH halves of that
      # contract, so neither the removal nor the replacement can regress
      # unnoticed.
      it "refuses raw HDF -> POA&M, which is removed upstream by design" do
        expect {
          HdfOscalTranslationService.new.hdf_to_oscal_poam(hdf_fixture)
        }.to raise_error(HdfRunner::Error, /no converter found/)
      end

      it "produces a POA&M from HDF Amendments — the supported route" do
        # Round-trip through the pair, starting from SPARC'S OWN export: an
        # OSCAL POA&M converts to HDF Amendments, and those amendments convert
        # back to an OSCAL POA&M. Both directions run, so a regression in
        # either converter surfaces here — and starting from our export means
        # this also proves what SPARC emits is consumable by the toolchain,
        # which a canned fixture could not.
        service = HdfOscalTranslationService.new

        amendments = Tempfile.create([ "sparc-poam-", ".json" ]) do |src|
          src.write(OscalPoamExportService.new(authored_poam).export)
          src.flush
          service.oscal_poam_to_hdf_amendments(src.path)
        end
        expect(amendments).to be_present

        Tempfile.create([ "amendments-", ".json" ]) do |f|
          f.write(JSON.generate(amendments))
          f.flush

          round_tripped = service.oscal_poam_from_hdf_amendments(f.path)
          expect(round_tripped).to have_key("plan-of-action-and-milestones")
        end
      end

      it "merges boundary evidence into OSCAL back-matter" do
        ab = create(:authorization_boundary)
        evidence = create(:evidence, authorization_boundary: ab)

        oscal = HdfOscalTranslationService.new.hdf_to_oscal_sar(hdf_fixture, boundary: ab)
        resources = oscal.dig("assessment-results", "back-matter", "resources") || []

        expect(resources).to be_present,
          "boundary evidence was not merged into back-matter"
        expect(evidence).to be_persisted
      end
    end

    describe "POA&M" do
      it "exports as a schema-valid plan-of-action-and-milestones (JSON + YAML)" do
        json = OscalPoamExportService.new(authored_poam).export

        expect_valid_json_and_yaml(json, model_type: :poam, label: "Stage 5 POA&M")
      end

      it "REJECTS a POA&M with no items — the schema requires at least one" do
        # The OSCAL POA&M root requires uuid, metadata and poam-items, and
        # poam-items has minItems 1: a plan of action with no actions in it is
        # not a plan. (system-id is NOT required — worth stating, because it
        # reads like it ought to be.)
        json = OscalPoamExportService.new(authored_poam).export

        expect_rejected_by_schema(json, model_type: :poam, label: "Stage 5 POA&M") do |data|
          data["plan-of-action-and-milestones"]["poam-items"] = []
        end
      end

      it "REJECTS a POA&M whose risk carries no statement (#816 guard)" do
        # The #816 guard, pinned: OSCAL requires risk/statement, and the
        # exporter must never invent one.
        json = OscalPoamExportService.new(authored_poam).export

        expect_rejected_by_schema(json, model_type: :poam, label: "Stage 5 POA&M") do |data|
          data["plan-of-action-and-milestones"]["risks"].each { |r| r.delete("statement") }
        end
      end
    end
  end

  # ── S6 — the negative sweep ──────────────────────────────────────────────
  #
  # Stages 1-5 each carry their own reject cases. This closes the two gaps
  # #817 names explicitly and that per-stage assertions cannot cover, because
  # both are about combinations ACROSS types:
  #
  #   "wrong-schema-for-type"  — validating a document as the wrong model
  #   "unsupported combinations handled deliberately (clear rejection, not a
  #    crash)" — feeding a parser a format it does not serve
  describe "S6 — cross-type negative sweep" do
    # One known-good document per OSCAL model, from committed fixtures rather
    # than generated, so this sweep is cheap and independent of the pipeline
    # stages above — a failure here is about SCHEMA SELECTION, not generation.
    MODEL_FIXTURES = {
      catalog: "profiles/small-resolved-profile-catalog.json",
      profile: "profiles/NIST_SP-800-53_rev5_LOW-baseline_profile.json",
      ssp: "ssp/oscal_leveraging-example_ssp.json",
      assessment_plan: "sap/ifa_assessment-plan.json",
      assessment_results: "sar/ifa_assessment-results.json",
      poam: "poam/ifa_plan-of-action-and-milestones.json",
      component_definition: "components/example-component-definition.json"
    }.freeze

    def fixture_json(relative)
      Rails.root.join("spec/fixtures/files", relative).read
    end

    # The control. If a fixture does not satisfy its OWN schema, every
    # cross-type rejection below could be explained by the fixture being bad
    # rather than by the validator selecting correctly.
    it "each fixture is valid against its OWN model schema" do
      MODEL_FIXTURES.each do |model, path|
        result = OscalSchemaValidationService.validate_json(model, fixture_json(path))

        expect(result.valid?).to be(true),
          -> { "#{path} is not valid #{model}: #{Array(result.errors).first(3).join('; ')}" }
      end
    end

    it "REJECTS every document validated as a model it is not" do
      # 7 models × 6 wrong schemas = 42 combinations. A validator that ignored
      # its model_type argument, or defaulted to a permissive schema, would
      # pass every positive assertion in this file and fail only here.
      accepted = []

      MODEL_FIXTURES.each do |actual_model, path|
        json = fixture_json(path)

        MODEL_FIXTURES.each_key do |candidate_model|
          next if candidate_model == actual_model

          result = OscalSchemaValidationService.validate_json(candidate_model, json)
          accepted << "#{actual_model} accepted as #{candidate_model}" if result.valid?
        end
      end

      expect(accepted).to be_empty,
        "the validator accepted documents as the wrong model:\n  #{accepted.join("\n  ")}"
    end

    it "REJECTS malformed input for every model rather than accepting a shell" do
      malformed = {
        "empty object" => "{}",
        "null root" => "null",
        "array root" => "[]",
        "right key, empty body" => '{"catalog": {}}'
      }

      accepted = []
      MODEL_FIXTURES.each_key do |model|
        malformed.each do |label, payload|
          result = OscalSchemaValidationService.validate_json(model, payload)
          accepted << "#{model} accepted #{label}" if result.valid?
        end
      end

      expect(accepted).to be_empty,
        "the validator accepted malformed input:\n  #{accepted.join("\n  ")}"
    end

    it "does not CRASH on malformed input — it reports invalid" do
      # The distinction matters: a raised exception surfaces to an API caller
      # as a 500, an invalid result as a 422. #817 asks for deliberate
      # rejection, which means the former is a bug even though both "fail".
      [ "not json at all", "{unclosed", '{"catalog": ', " " ].each do |payload|
        expect {
          OscalSchemaValidationService.validate_json(:catalog, payload)
        }.not_to raise_error, "validator crashed instead of rejecting: #{payload.inspect}"
      end
    end

    # The ODP constraint case #817 calls out by name. A selection value outside
    # the baseline's allowed choices must not reach the database.
    it "REJECTS an ODP selection whose value is not an allowed choice" do
      profile = create(:profile_document, name: "ODP constraint target", baseline_level: "LOW",
                                          control_catalog: catalog)
      ProfileControlSelectionService.new(profile).update(%w[ac-1 ac-2])

      payload = OdpImportService.parse(
        content: { selections: [ { select_id: "ac-2_prm_1", selected: [ "not-an-allowed-choice" ] } ] }.to_json,
        format: "json"
      )
      preview = OdpImportService.new(profile.reload).preview(payload)

      statuses = preview[:rows].map(&:status)
      expect(statuses).to all(satisfy { |s| %w[invalid unknown].include?(s) }),
        "an out-of-range ODP choice was previewed as an acceptable change: #{statuses.inspect}"
    end
  end
end
