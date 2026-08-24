# frozen_string_literal: true

require "rails_helper"

# Release gate: every OSCAL document type SPARC produces must validate against
# the version SPARC declares it produces (#1020).
#
# The per-type export specs each assert their own shape, but none of them asks
# the question that matters when DEFAULT_VERSION moves: does *every* type still
# conform to the new default? That gap is why moving the default was previously
# deferred rather than decided — there was nothing that could answer it.
#
# The default moved 1.1.2 -> 1.2.2 on 2026-08-23 by owner decision. 1.2.x is not
# a cosmetic bump: it applies the non-empty-string datatype to `metadata.title`
# and sibling title fields that 1.1.x left unconstrained, so a type that
# satisfied 1.1.2 does not automatically satisfy 1.2.2. This spec is what makes
# that claim checkable, on every type, on every run.
#
# `export` is the production path and validates as a side effect. This spec uses
# `export_unvalidated` on purpose: it isolates the SHAPE of what SPARC builds
# from the gate that would otherwise mask a defect by refusing to emit it, so a
# regression is reported here rather than surfacing as a failed export.
#
# NIST SA-10: Developer Configuration Management
RSpec.describe "OSCAL conformance at the default version" do
  let(:version) { OscalSchema::DEFAULT_VERSION }

  # Without a DB row for the requested version, the validator falls back to the
  # single unversioned schema set in `lib/oscal_schemas/` and reports success —
  # so a spec that merely passes `version:` proves nothing about that version.
  # Seed the real schemas from the offline bundle, the same source
  # `oscal:seed_schemas` uses, and verify the checksum the manifest records.
  # Seeded per example, INSIDE the transaction, so it rolls back.
  #
  # This was a `before(:all)` for speed and it silently broke two unrelated
  # importer specs: `before(:all)` runs outside the per-example transaction, so
  # the rows survived the whole run, and `SparcConfig#aws_labs_oscal_versions`
  # derives its allowlist from the DISTINCT oscal_version values in this table.
  # An empty table means "accept any version"; a table holding only 1.2.2 means
  # "reject 1.1.2", so the AWS Labs importer silently accepted nothing and
  # reported neither an import nor an error. Shared mutable state written
  # outside a transaction is not a local decision.
  #
  # The schemas come from `lib/oscal_schemas/`, which is TRACKED, rather than
  # `lib/oscal_schemas_bundle/`, which is gitignored and generated during the
  # Docker build — CI has no bundle, so a spec reading it would not run there.
  before do
    OscalSchema::DOCUMENT_TYPE_MAP.each do |doc_type, config|
      next if doc_type.to_s == "mapping" && !OscalSchema::MAPPING_VERSIONS.include?(OscalSchema::DEFAULT_VERSION)

      raw = JSON.parse(File.read(Rails.root.join("lib/oscal_schemas", config[:file])))
      row = OscalSchema.find_or_initialize_by(oscal_version: OscalSchema::DEFAULT_VERSION,
                                              document_type: doc_type.to_s,
                                              schema_format: "json")
      row.assign_attributes(raw_schema: raw,
                            preprocessed_schema: OscalSchema.preprocess_schema(raw),
                            root_key: config[:root_key],
                            source_url: "disk://#{config[:file]}",
                            active: true)
      row.save!
    end
    OscalSchemaValidationService.clear_cache!
  end

  # The schema cache is keyed by [model_type, version] and is process-global, so
  # it outlives the rolled-back rows it was built from.
  after { OscalSchemaValidationService.clear_cache! }

  def validate(model_type, json)
    data = json.is_a?(String) ? JSON.parse(json) : json
    OscalSchemaValidationService.validate(model_type, data, version: version)
  end

  def expect_conformant(model_type, json)
    result = validate(model_type, json)
    valid  = result.respond_to?(:valid?) ? result.valid? : result[:valid]
    errors = Array(result.respond_to?(:errors) ? result.errors : result[:errors])

    expect(valid).to be(true),
      "#{model_type} does not validate against OSCAL #{version}, the version SPARC " \
      "declares in metadata.oscal-version. #{errors.size} error(s); first: " \
      "#{errors.first.inspect}"
  end

  it "declares a default it can actually validate against" do
    expect(OscalSchema::SUPPORTED_VERSIONS).to include(OscalSchema::DEFAULT_VERSION)
    expect(OscalSchema::KNOWN_DEFECTIVE_VERSIONS).not_to have_key(OscalSchema::DEFAULT_VERSION)
  end

  # Every environment that has not seeded the DB falls back to this tracked set,
  # and the fallback happens SILENTLY — the validator logs and carries on. The
  # set used to be a mixed bag (six files at 1.1.2, catalog and mapping at
  # 1.2.1), so "validate against 1.2.2" could quietly check against 1.1.2. If
  # DEFAULT_VERSION moves again, these files move with it.
  it "ships a tracked fallback schema set at the default version" do
    mismatched = OscalSchema::DOCUMENT_TYPE_MAP.filter_map do |doc_type, config|
      next if doc_type.to_s == "mapping" && !OscalSchema::MAPPING_VERSIONS.include?(version)

      path = Rails.root.join("lib/oscal_schemas", config[:file])
      id   = JSON.parse(File.read(path))["$id"].to_s
      declared = id[%r{/oscal/([\d.]+)/}, 1]
      "#{config[:file]} declares #{declared || '(no $id)'}" unless declared == version
    end

    expect(mismatched).to be_empty,
      "lib/oscal_schemas/ does not match DEFAULT_VERSION (#{version}): " \
      "#{mismatched.join('; ')}. Any environment without seeded schemas validates " \
      "against these files while reporting the default version, so a mismatch is " \
      "a validation that silently checks the wrong thing."
  end

  it "actually loads the default version rather than falling back" do
    catalog = create(:control_catalog, name: "Fallback Probe")
    family  = create(:control_family, control_catalog: catalog, code: "AC", name: "Access Control", sort_order: 1)
    create(:catalog_control, control_family: family, control_id: "ac-1", title: "Policy")

    result = validate(:catalog, OscalCatalogExportService.new(catalog).export_unvalidated)
    expect(result.schema_version).to eq(version)
    expect(OscalSchema.exists?(document_type: "catalog", oscal_version: version)).to be(true)
  end

  describe "catalog" do
    let(:catalog) { create(:control_catalog, name: "Conformance Catalog") }
    let!(:family) { create(:control_family, control_catalog: catalog, code: "AC", name: "Access Control", sort_order: 1) }
    let!(:control) do
      create(:catalog_control, control_family: family, control_id: "ac-1", title: "Policy and Procedures")
    end

    it "conforms" do
      expect_conformant(:catalog, OscalCatalogExportService.new(catalog).export_unvalidated)
    end
  end

  describe "profile" do
    let(:catalog) { create(:control_catalog, name: "Reference Catalog") }
    let(:profile) { create(:profile_document, name: "Conformance Profile", control_catalog: catalog) }
    let!(:control) { create(:profile_control, profile_document: profile, control_id: "ac-1") }

    it "conforms" do
      expect_conformant(:profile, OscalProfileExportService.new(profile).export_unvalidated)
    end
  end

  describe "system security plan" do
    let(:boundary) { create(:authorization_boundary) }
    let(:ssp) { create(:ssp_document, :enriched, name: "Conformance SSP", authorization_boundary: boundary) }
    # OSCAL requires at least one implemented-requirement; an SSP with no
    # controls is not a schema regression, just an empty document.
    let!(:control) { create(:ssp_control, ssp_document: ssp, control_id: "ac-1") }

    it "conforms" do
      expect_conformant(:ssp, OscalSspExportService.new(ssp).export_unvalidated)
    end
  end

  describe "component definition" do
    let(:cdef) { create(:cdef_document, name: "Conformance CDEF") }
    let!(:control) { create(:cdef_control, cdef_document: cdef, control_id: "ac-1") }

    it "conforms" do
      expect_conformant(:component_definition,
                        OscalComponentDefinitionExportService.new(cdef).export_unvalidated)
    end
  end

  describe "assessment plan" do
    let(:sap) { create(:sap_document, name: "Conformance SAP") }
    let!(:control) { create(:sap_control, sap_document: sap, control_id: "ac-1") }

    it "conforms" do
      expect_conformant(:assessment_plan,
                        OscalAssessmentPlanExportService.new(sap).export_unvalidated)
    end
  end

  describe "assessment results" do
    let(:sar) { create(:sar_document, :enriched, name: "Conformance SAR") }
    let!(:control) { create(:sar_control, sar_document: sar, control_id: "ac-1") }

    it "conforms" do
      expect_conformant(:assessment_results, OscalSarExportService.new(sar).export_unvalidated)
    end
  end

  describe "plan of action and milestones" do
    let(:boundary) { create(:authorization_boundary) }
    let(:poam) { create(:poam_document, name: "Conformance POA&M", authorization_boundary: boundary) }
    let!(:item) { create(:poam_item, poam_document: poam, title: "An item") }

    it "conforms" do
      expect_conformant(:poam, OscalPoamExportService.new(poam).export_unvalidated)
    end
  end
end
