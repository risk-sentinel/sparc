require "rails_helper"

# Cross-cutting OSCAL compliance audit — verifies all exports follow
# OSCAL specification rules for UUIDs, hrefs, back-matter, versioning,
# and metadata completeness.
RSpec.describe "OSCAL Compliance Audit", type: :service do
  UUID_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  # ── Helper: parse export output ──────────────────────────────────

  def export_json(service)
    JSON.parse(service.export_unvalidated)
  end

  # ── Shared examples ──────────────────────────────────────────────

  shared_examples "OSCAL metadata compliance" do |root_key|
    it "has a valid root UUID" do
      uuid = output[root_key]["uuid"]
      expect(uuid).to match(UUID_REGEX), "Root UUID '#{uuid}' is not RFC 4122 format"
    end

    it "has required metadata fields" do
      metadata = output[root_key]["metadata"]
      expect(metadata).to be_present
      expect(metadata["title"]).to be_present
      expect(metadata["oscal-version"]).to be_present
      expect(metadata["last-modified"]).to be_present
    end

    it "has a valid oscal-version format" do
      version = output[root_key]["metadata"]["oscal-version"]
      expect(version).to match(/\A\d+\.\d+\.\d+\z/), "oscal-version '#{version}' is not semver"
    end

    it "has last-modified as ISO 8601" do
      last_modified = output[root_key]["metadata"]["last-modified"]
      expect { Time.iso8601(last_modified) }.not_to raise_error,
        "last-modified '#{last_modified}' is not ISO 8601"
    end
  end

  shared_examples "OSCAL back-matter compliance" do |root_key|
    it "has a back-matter section" do
      back_matter = output[root_key]["back-matter"]
      expect(back_matter).to be_present
    end

    it "has a SPARC back-matter resource" do
      resources = output[root_key].dig("back-matter", "resources") || []
      sparc_resource = resources.find { |r| r["title"]&.include?("SPARC") }
      expect(sparc_resource).to be_present, "No SPARC back-matter resource found"
    end

    it "has valid UUIDs on all back-matter resources" do
      resources = output[root_key].dig("back-matter", "resources") || []
      resources.each do |resource|
        expect(resource["uuid"]).to match(UUID_REGEX),
          "Back-matter resource UUID '#{resource['uuid']}' is not RFC 4122"
      end
    end
  end

  shared_examples "OSCAL UUID stability" do |root_key|
    it "preserves the document UUID across re-exports" do
      uuid1 = output[root_key]["uuid"]
      output2 = export_json(service)
      uuid2 = output2[root_key]["uuid"]
      expect(uuid2).to eq(uuid1), "UUID changed between exports: #{uuid1} → #{uuid2}"
    end
  end

  # ── SSP Compliance ───────────────────────────────────────────────

  describe "SSP export compliance" do
    let(:ssp_document) { create(:ssp_document, name: "Audit SSP", oscal_version: "1.1.2") }
    let!(:ssp_control) do
      create(:ssp_control, ssp_document: ssp_document, control_id: "ac-1")
    end
    let(:service) { OscalSspExportService.new(ssp_document) }
    let(:output) { export_json(service) }

    include_examples "OSCAL metadata compliance", "system-security-plan"
    include_examples "OSCAL back-matter compliance", "system-security-plan"
    include_examples "OSCAL UUID stability", "system-security-plan"

    it "has an import-profile section" do
      import_profile = output["system-security-plan"]["import-profile"]
      expect(import_profile).to be_present
      expect(import_profile["href"]).to be_present
    end

    it "exports the correct oscal-version from the document" do
      version = output["system-security-plan"]["metadata"]["oscal-version"]
      expect(version).to eq("1.1.2")
    end
  end

  # ── CDEF Compliance ──────────────────────────────────────────────

  describe "CDEF export compliance" do
    let(:cdef_document) { create(:cdef_document, name: "Audit CDEF", oscal_version: "1.1.2") }
    let!(:cdef_control) do
      create(:cdef_control, cdef_document: cdef_document, control_id: "ac-1")
    end
    let(:service) { OscalComponentDefinitionExportService.new(cdef_document) }
    let(:output) { export_json(service) }

    include_examples "OSCAL metadata compliance", "component-definition"
    include_examples "OSCAL back-matter compliance", "component-definition"
    include_examples "OSCAL UUID stability", "component-definition"
  end

  # ── SAR Compliance ──────────────────────────────────────────────

  describe "SAR export compliance" do
    let(:sar_document) { create(:sar_document, name: "Audit SAR", oscal_version: "1.1.2") }
    let!(:sar_control) do
      create(:sar_control, sar_document: sar_document, control_id: "ac-1")
    end
    let(:service) { OscalSarExportService.new(sar_document) }
    let(:output) { export_json(service) }

    include_examples "OSCAL metadata compliance", "assessment-results"
    include_examples "OSCAL back-matter compliance", "assessment-results"
    include_examples "OSCAL UUID stability", "assessment-results"
  end

  # ── Profile Compliance ──────────────────────────────────────────

  describe "Profile export compliance" do
    let(:catalog) { create(:control_catalog) }
    let(:profile_document) do
      create(:profile_document, name: "Audit Profile", oscal_version: "1.1.2",
             control_catalog: catalog)
    end
    let(:service) { OscalProfileExportService.new(profile_document) }
    let(:output) { export_json(service) }

    include_examples "OSCAL metadata compliance", "profile"
    include_examples "OSCAL back-matter compliance", "profile"
    include_examples "OSCAL UUID stability", "profile"
  end

  # ── POA&M Compliance ────────────────────────────────────────────

  describe "POA&M export compliance" do
    let(:poam_document) { create(:poam_document, name: "Audit POA&M") }
    let(:service) { OscalPoamExportService.new(poam_document) }
    let(:output) { export_json(service) }

    include_examples "OSCAL metadata compliance", "plan-of-action-and-milestones"
    include_examples "OSCAL back-matter compliance", "plan-of-action-and-milestones"
    include_examples "OSCAL UUID stability", "plan-of-action-and-milestones"
  end

  # ── Version consistency ─────────────────────────────────────────

  describe "version consistency" do
    it "OscalSchema.DEFAULT_VERSION matches validation service default" do
      expect(OscalSchema::DEFAULT_VERSION).to eq(OscalSchemaValidationService::DEFAULT_OSCAL_VERSION)
    end

    it "all export services reference OscalSchema::DEFAULT_VERSION" do
      services = [
        OscalSspExportService,
        OscalComponentDefinitionExportService,
        OscalSarExportService,
        OscalProfileExportService,
        OscalPoamExportService,
        OscalAssessmentPlanExportService,
        OscalCatalogExportService,
        OscalResolvedProfileCatalogService
      ]

      services.each do |service_class|
        expect(service_class::DEFAULT_OSCAL_VERSION).to eq(OscalSchema::DEFAULT_VERSION),
          "#{service_class}::DEFAULT_OSCAL_VERSION (#{service_class::DEFAULT_OSCAL_VERSION}) != OscalSchema::DEFAULT_VERSION (#{OscalSchema::DEFAULT_VERSION})"
      end
    end

    it "mapping service defaults to 1.2.1" do
      expect(OscalMappingExportService::DEFAULT_OSCAL_VERSION).to eq("1.2.1")
    end
  end
end
