# frozen_string_literal: true

require "rails_helper"

# The sample OSCAL documents in spec/fixtures/files/end_to_end/, for testing an
# instance by hand: a tailored NIST Rev 5 MODERATE baseline, the SSP built
# from it with every part and enhancement answered, the assessment plan, and
# the assessment results with objectives determined.
#
# Every run checks the committed files are valid OSCAL 1.2.3 and complete.
# They are produced by SPARC's own pipeline, never written by hand:
#
#   WRITE_E2E_SAMPLES=1 bundle exec rspec spec/integration/end_to_end_samples_spec.rb
#
# regenerates them from spec/fixtures/files/profiles/NIST_SP-800-53_rev5_MODERATE-tailored_profile.json
# (itself from bin/generate_tailored_profile_fixture.rb).
RSpec.describe "end-to-end OSCAL samples" do
  let(:fixtures) { Rails.root.join("spec/fixtures/files") }
  let(:dir) { fixtures.join("end_to_end") }

  def sample_path(name) = dir.join(name)

  # file => [OSCAL model, root key]
  def samples
    {
      "ssp-nist-rev5-moderate-tailored.json" => [ :ssp, "system-security-plan" ],
      "sap-nist-rev5-moderate-tailored.json" => [ :assessment_plan, "assessment-plan" ],
      "sar-nist-rev5-moderate-tailored.json" => [ :assessment_results, "assessment-results" ]
    }
  end

  if ENV["WRITE_E2E_SAMPLES"] == "1"
    it "regenerates the samples through the pipeline" do
      import = lambda do |name|
        CatalogImportService.call(File.open(fixtures.join("catalogs", name)), name)[:catalog].tap do |c|
          c.update_columns(lifecycle_status: "published")
        end
      end
      import.call("NIST_SP-800-53_rev5_catalog.json")
      import.call("NIST_SP-800-53_rev4_catalog.json")

      profile_path = fixtures.join("profiles/NIST_SP-800-53_rev5_MODERATE-tailored_profile.json")
      profile = create(:profile_document, name: "NIST Rev 5 MODERATE (tailored sample)", status: "processing",
                                          file_type: "json", original_filename: File.basename(profile_path))
      ProfileJsonParserService.new(profile, profile_path.to_s).parse
      profile.reload.profile_controls.update_all(priority: "P1")
      profile.update!(resolved_catalog_json: JSON.parse(OscalResolvedProfileCatalogService.new(profile.reload).export),
                      lifecycle_status: "published")

      boundary = create(:authorization_boundary, name: "Sample System")
      ssp = SspFromProfileService.new(profile, name: "Sample System SSP (NIST Rev 5 MODERATE, tailored)",
                                               authorization_boundary: boundary).create
      SspControlStatement.joins(:ssp_control).where(ssp_controls: { ssp_document_id: ssp.id }).find_each do |s|
        s.update!(implementation_prose: "Sample System implements #{s.statement_id}: <describe how>.")
      end
      ssp.ssp_controls.each do |control|
        control.ssp_control_fields.find_by(field_name: "status")&.update!(field_value: "Implemented")
      end

      sap = SapGeneratorService.new(name: "Sample System assessment plan", ssp_document: ssp.reload).generate
      sar = SarFromSspService.new(ssp, name: "Sample System assessment results").create
      # Determine every determinable objective: most satisfied, every seventh not.
      SarControlObjective.joins(:sar_control).where(sar_controls: { sar_document_id: sar.id })
                         .order(:id).reject(&:container?).each_with_index do |objective, i|
        objective.update!(status: (i % 7).zero? ? "failed" : "passing")
      end

      FileUtils.mkdir_p(dir)
      File.write(sample_path("ssp-nist-rev5-moderate-tailored.json"), OscalSspExportService.new(ssp.reload).export)
      File.write(sample_path("sap-nist-rev5-moderate-tailored.json"), OscalAssessmentPlanExportService.new(sap.reload).export_unvalidated)
      File.write(sample_path("sar-nist-rev5-moderate-tailored.json"), OscalSarExportService.new(sar.reload).export_unvalidated)
    end
  end

  it "keeps every sample valid OSCAL 1.2.3" do
    samples.each do |file, (model, root)|
      data = JSON.parse(File.read(sample_path(file)))
      expect(data).to have_key(root), file
      expect(OscalSchemaValidationService.validate(model, data, version: "1.2.3").errors).to be_empty, file
    end
  end

  it "has every part and enhancement answered in the SSP sample" do
    data = JSON.parse(File.read(sample_path("ssp-nist-rev5-moderate-tailored.json")))
    requirements = data.dig("system-security-plan", "control-implementation", "implemented-requirements")
    statements = requirements.flat_map { |ir| Array(ir["statements"]) }

    expect(requirements.size).to eq(287)
    expect(requirements.count { |ir| ir["control-id"].include?(".") }).to eq(110)
    unanswered = statements.reject { |s| s.dig("by-components", 0, "description").to_s.start_with?("Sample System implements") }
    expect(unanswered.map { |s| s["statement-id"] }).to be_empty
  end

  it "names objectives as objectives in the plan and results samples" do
    sap = JSON.parse(File.read(sample_path("sap-nist-rev5-moderate-tailored.json")))
    expect(sap.dig("assessment-plan", "reviewed-controls", "control-objective-selections", 0, "include-objectives")).to be_present

    sar = JSON.parse(File.read(sample_path("sar-nist-rev5-moderate-tailored.json")))
    targets = sar.dig("assessment-results", "results").flat_map { |r| Array(r["findings"]) }.map { |f| f["target"] }
    objective_targets = targets.select { |t| t["type"] == "objective-id" }
    expect(objective_targets).not_to be_empty
    expect(objective_targets.map { |t| t["target-id"] }).to all(include("_obj"))
  end
end
