# frozen_string_literal: true

require "rails_helper"

# NIST's Rev 5 catalog, a consumer's tailored MODERATE profile, the SSP built
# from it, every part and enhancement answered, and the OSCAL that comes out.
#
# Each of these broke without any test noticing, because no test followed a
# real NIST baseline with real parameter values all the way through:
#
#   - profile import dropped every Rev 5 parameter id (`ac-01_odp.05`), so a
#     consumer's whole set of policy values vanished on upload;
#   - aggregate parameters (`ac-1_prm_1`) ignored the values set on their parts;
#   - building a baseline seeded each parameter with its catalog LABEL, which
#     the screens and the export then presented as a chosen value;
#   - SSP generation stored no requirement for 127 of the 287 controls;
#   - the SSP screen's response rows showed "a." and "(b)" with no text, only
#     in view mode, so an author in the edit form had no way to answer a part;
#   - with Rev 4 loaded too (seeds load both), a Rev 5 SSP showed Rev 4 text.
#
# The fixture is generated (bin/generate_tailored_profile_fixture.rb): every
# settable parameter of the MODERATE baseline, 584 of them.
RSpec.describe "NIST Rev 5 MODERATE, end to end", type: :request do
  let(:fixtures) { Rails.root.join("spec/fixtures/files") }
  let(:tailored_path) { fixtures.join("profiles/NIST_SP-800-53_rev5_MODERATE-tailored_profile.json") }
  let(:tailored) { JSON.parse(File.read(tailored_path)) }
  let(:set_parameters) { tailored.dig("profile", "modify", "set-parameters").to_h { |p| [ p["param-id"], p["values"] ] } }

  let!(:rev5) { import_catalog("NIST_SP-800-53_rev5_catalog.json") }
  let!(:rev4) { import_catalog("NIST_SP-800-53_rev4_catalog.json") }

  def import_catalog(name)
    CatalogImportService.call(File.open(fixtures.join("catalogs", name)), name)[:catalog].tap do |catalog|
      catalog.update_columns(lifecycle_status: "published")
    end
  end

  def import_profile(path)
    create(:profile_document, status: "processing", file_type: "json", original_filename: File.basename(path)).tap do |doc|
      ProfileJsonParserService.new(doc, path.to_s).parse
      doc.reload
    end
  end

  def publish!(profile)
    profile.profile_controls.update_all(priority: "P1")
    resolved = JSON.parse(OscalResolvedProfileCatalogService.new(profile.reload).export)
    profile.update!(resolved_catalog_json: resolved, lifecycle_status: "published")
    profile
  end

  def stored_parameters(profile)
    ProfileControlField.joins(:profile_control)
                       .where(profile_controls: { profile_document_id: profile.id })
                       .where("field_name LIKE 'parameter:%'")
                       .pluck(:field_name, :field_value)
                       .to_h { |name, value| [ name.delete_prefix("parameter:"), value ] }
  end

  # Statement rows the catalog defines for a set of controls: the `statement`
  # part and every `item` under it, by NIST id.
  def catalog_statement_part_ids(catalog, control_ids)
    CatalogControlPart.joins(catalog_control: :control_family)
                      .where(control_families: { control_catalog_id: catalog.id })
                      .where(catalog_controls: { control_id: control_ids })
                      .where(part_name: %w[statement item])
                      .pluck(:part_id)
  end

  let(:profile) { publish!(import_profile(tailored_path)) }
  let(:ssp) { SspFromProfileService.new(profile, authorization_boundary: create(:authorization_boundary)).create }
  let(:control_ids) { profile.profile_controls.pluck(:control_id) }

  it "uses a fixture the OSCAL 1.2.3 profile schema accepts, carrying every settable parameter" do
    expect(OscalSchemaValidationService.validate(:profile, tailored, version: "1.2.3").errors).to be_empty
    expect(set_parameters.size).to eq(584)
    expect(set_parameters["ac-01_odp.05"]).to eq([ "365" ])
  end

  it "imports the tailored profile against Rev 5 with every parameter value it carries" do
    expect(profile.control_catalog).to eq(rev5)
    expect(control_ids.size).to eq(287)
    expect(control_ids.count { |id| id.include?(".") }).to eq(110)

    stored = stored_parameters(profile)
    missing = set_parameters.reject { |id, values| stored[id] == values.join(", ") }
    expect(missing.keys).to be_empty, "#{missing.size} of #{set_parameters.size} set-parameters not stored, e.g. #{missing.first(5).map(&:first)}"
    expect(stored["ac-01_odp.05"]).to eq("365")
  end

  it "resolves the baseline with the consumer's values, aggregates included, and no raw markup" do
    # Every statement and item a reader sees is fully resolved. (A parameter's
    # own definition may still name another parameter, as NIST's catalog does
    # in sa-11_odp.01's guidelines; that is the definition, not the requirement.)
    unresolved = []
    ResolvedCatalog.wrap(profile.resolved_catalog_json).each_control do |control, _group|
      walk = lambda do |parts|
        Array(parts).each do |part|
          unresolved << part["id"] if %w[statement item].include?(part["name"]) && part["prose"].to_s.include?("{{ insert: param")
          walk.call(part["parts"])
        end
      end
      walk.call(control["parts"])
    end
    expect(unresolved).to be_empty

    ac1 = ControlRequirementText.for_profile(profile).for_control("ac-1")
    # Through aggregate ac-1_prm_1, which stands for both of its parts.
    expect(ac1.for_part("ac-1_smt.a"))
      .to include("#{set_parameters["ac-01_odp.01"].first}, #{set_parameters["ac-01_odp.02"].first}")
    expect(ac1.for_part("ac-1_smt.c.1")).to include("365")
  end

  it "builds an SSP with every control, enhancement and statement part, each with its requirement text" do
    rows = ssp.ssp_controls.includes(:ssp_control_statements, :ssp_control_fields).to_a
    expect(rows.size).to eq(287)
    expect(rows.count { |c| c.control_id.include?(".") }).to eq(110)

    without_requirement = rows.select { |c| c.ssp_control_fields.find { |f| f.field_name == "stated_requirement" }&.field_value.blank? }
    expect(without_requirement.map(&:control_id)).to be_empty

    statement_ids = rows.flat_map { |c| c.ssp_control_statements.map(&:statement_id) }
    expect(statement_ids).to match_array(catalog_statement_part_ids(rev5, control_ids))

    texts = ControlRequirementText.for_profile(profile).for_controls(control_ids)
    leaves_without_text = rows.flat_map do |c|
      c.ssp_control_statements.reject { |s| texts[ControlId.canonical(c.control_id)]&.for_part(s.statement_id).present? }
                              .reject { |s| s.statement_id.end_with?("_smt") } # the control as a whole
                              .map(&:statement_id)
    end
    expect(leaves_without_text).to be_empty
  end

  it "exports every answered part as valid OSCAL 1.2.3 and imports it back unchanged" do
    statements = SspControlStatement.joins(:ssp_control).where(ssp_controls: { ssp_document_id: ssp.id })
    statements.find_each { |s| s.update!(implementation_prose: "Response to #{s.statement_id}.") }

    data = JSON.parse(OscalSspExportService.new(ssp.reload).export)
    expect(OscalSchemaValidationService.validate(:ssp, data, version: "1.2.3").errors).to be_empty

    exported = data.dig("system-security-plan", "control-implementation", "implemented-requirements")
                   .flat_map { |ir| Array(ir["statements"]) }
                   .reject { |s| s["statement-id"].end_with?("_priv", "_pub") }
    answered = statements.count
    expect(exported.size).to eq(answered)
    wrong = exported.reject { |s| s.dig("by-components", 0, "description") == "Response to #{s['statement-id']}." }
    expect(wrong.map { |s| s["statement-id"] }).to be_empty

    # Statement UUIDs are unique instance-wide and the export carries them, so
    # the file is received the way another instance would receive it: without
    # the original's statements already present.
    statements.delete_all

    path = Rails.root.join("tmp", "e2e_ssp_#{SecureRandom.hex(4)}.json").to_s
    File.write(path, JSON.generate(data))
    reimported = create(:ssp_document, status: "processing", file_type: "json", original_filename: "e2e.json")
    SspJsonParserService.new(reimported, path).parse
    FileUtils.rm_f(path)

    back = SspControlStatement.joins(:ssp_control).where(ssp_controls: { ssp_document_id: reimported.id })
                              .pluck(:statement_id, :implementation_prose).to_h
    expect(back.size).to eq(answered)
    expect(back.reject { |id, prose| prose == "Response to #{id}." }.keys).to be_empty
  end

  it "exports the baseline with exactly the consumer's values and nothing invented" do
    data = JSON.parse(OscalProfileExportService.new(profile).export)
    exported = Array(data.dig("profile", "modify", "set-parameters")).to_h { |p| [ p["param-id"], p["values"] ] }

    expect(exported.keys).to match_array(set_parameters.keys)
    expect(exported["ac-01_odp.05"]).to eq([ "365" ])
  end

  it "does not invent values when a baseline is built from the catalog" do
    built = create(:profile_document, control_catalog: rev5, status: "completed", lifecycle_status: "in_progress")
    ProfileControlSelectionService.new(built).update(%w[ac-1 ac-2])

    expect(stored_parameters(built).values.uniq).to eq([ "" ])
    expect(Array(JSON.parse(OscalProfileExportService.new(built).export_unvalidated).dig("profile", "modify", "set-parameters"))).to be_empty
  end

  describe "the assessment plan and results" do
    # 800-53A assessment objectives the catalog defines for the baseline.
    let(:catalog_objective_count) do
      CatalogControlPart.joins(catalog_control: :control_family)
                        .where(control_families: { control_catalog_id: rev5.id })
                        .where(catalog_controls: { control_id: control_ids })
                        .where(part_name: "assessment-objective").count
    end

    let(:sap) { SapGeneratorService.new(name: "E2E plan", ssp_document: ssp).generate }

    it "plans every objective of every control and enhancement, named as objectives, in valid OSCAL" do
      objectives = SapControlObjective.joins(:sap_control).where(sap_controls: { sap_document_id: sap.id })
      expect(objectives.count).to eq(catalog_objective_count)
      enhancements = sap.sap_controls.select { |c| c.control_id.include?(".") }
      expect(enhancements.size).to eq(110)
      # An enhancement's objective carries the consumer's values too: the plan
      # used to index only top-level controls of the resolved catalog.
      ac23 = sap.sap_controls.find_by(control_id: "ac-2.3").objective
      expect(ac23).to include(set_parameters.fetch("ac-02.03_odp.01").first)
      expect(ac23).not_to include("insert:")

      data = JSON.parse(OscalAssessmentPlanExportService.new(sap.reload).export_unvalidated)
      expect(OscalSchemaValidationService.validate(:assessment_plan, data, version: "1.2.3").errors).to be_empty

      named = data.dig("assessment-plan", "reviewed-controls", "control-objective-selections", 0, "include-objectives").map { |o| o["objective-id"] }
      expect(named.size).to eq(catalog_objective_count)
      statement_ids = data.to_json.scan(/"statement-ids":\[[^\]]*\]/).join
      expect(statement_ids).not_to include("_obj")
    end

    it "gives a SAR built from the SSP every objective, the whole requirement, and exports what an assessor determined" do
      sar = SarFromSspService.new(ssp).create
      objectives = SarControlObjective.joins(:sar_control).where(sar_controls: { sar_document_id: sar.id })
      expect(objectives.count).to eq(catalog_objective_count)

      leaves = objectives.reject(&:container?)
      leaves.first.update!(status: "passing")
      leaves.second.update!(status: "failed")

      data = JSON.parse(OscalSarExportService.new(sar.reload).export_unvalidated)
      expect(OscalSchemaValidationService.validate(:assessment_results, data, version: "1.2.3").errors).to be_empty

      targets = data.dig("assessment-results", "results", 0, "findings").map { |f| f["target"] }
      determined = targets.select { |t| t["type"] == "objective-id" }.to_h { |t| [ t["target-id"], t.dig("status", "state") ] }
      expect(determined).to eq(leaves.first.objective_id => "satisfied", leaves.second.objective_id => "not-satisfied")

      # A control id is never presented as an objective.
      expect(targets.select { |t| t["type"] == "objective-id" }.map { |t| t["target-id"] }).to all(include("_obj"))
    end

    it "gives a SAR built from the baseline the whole requirement of every control" do
      sar = SarFromProfileService.new(profile, authorization_boundary: create(:authorization_boundary)).create
      blank = sar.sar_controls.includes(:sar_control_fields).reject do |c|
        c.sar_control_fields.find { |f| f.field_name == "stated_requirement" }&.field_value.present?
      end
      expect(blank.map(&:control_id)).to be_empty
      expect(SarControlObjective.joins(:sar_control).where(sar_controls: { sar_document_id: sar.id }).count).to eq(catalog_objective_count)
    end
  end

  describe "the SSP screen" do
    before { sign_in_as(create(:user, :admin)) }

    it "shows each part's requirement, with the consumer's values, beside its response row, in Rev 5 language" do
      get ssp_document_path(ssp)
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)

      card = page.css(".control-card").find { |c| c.at_css(".sparc-ctrl-id")&.text&.strip == "ac-1" }
      rows = card.css("tr[data-statement-id]")
      expect(rows.size).to eq(ssp.ssp_controls.find_by(control_id: "ac-1").ssp_control_statements.count)

      c1 = rows.find { |r| r["data-statement-id"] == "ac-1_smt.c.1" }
      expect(c1.at_css("[data-statement-requirement]").text).to include("365")

      # Outside the view/edit toggle, so an author in the edit form can answer it.
      expect(c1.ancestors("[id^='view-']")).to be_empty
      expect(c1.ancestors("[id^='edit-']")).to be_empty

      au2 = page.css(".control-card").find { |c| c.at_css(".sparc-ctrl-id")&.text&.strip == "au-2" }
      expect(au2.text).not_to include("The organization:") # Rev 4's wording
    end

    it "gives each enhancement its own answerable row with its requirement" do
      get ssp_document_path(ssp)
      page = Nokogiri::HTML(response.body)
      card = page.css(".control-card").find { |c| c.at_css(".sparc-ctrl-id")&.text&.strip == "ac-2.1" }
      row = card.at_css("tr[data-statement-id='ac-2.1_smt']")

      expect(row).to be_present
      expect(row.at_css("[data-statement-requirement]").text).to include("Support the management of system accounts")
      expect(row.at_css("textarea[name='ssp_control_statement[implementation_prose]']")).to be_present
    end
  end
end
