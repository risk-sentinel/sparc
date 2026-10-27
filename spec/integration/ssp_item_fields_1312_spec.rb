# frozen_string_literal: true

require "rails_helper"

# #1312 — every item an SSP answers (no item below it, at any depth) records
# its own response, status, origination, responsible roles and expected
# completion; lead-ins take no input; the SP 800-53A objectives that test each
# item are listed under it, with the assessor's determination read-only; and
# the SAP, SAR and heatmap read the items. Built on NIST's own Rev 5 catalog and
# the tailored MODERATE baseline, as an author would.
RSpec.describe "SSP items, each answered in full (#1312)", type: :request do
  let(:fixtures) { Rails.root.join("spec/fixtures/files") }

  let!(:nist) do
    CatalogImportService.call(File.open(fixtures.join("catalogs/NIST_SP-800-53_rev5_catalog.json")),
                              "NIST_SP-800-53_rev5_catalog.json")[:catalog].tap do |catalog|
      catalog.update_columns(lifecycle_status: "published")
    end
  end

  let(:profile) do
    path = fixtures.join("profiles/NIST_SP-800-53_rev5_MODERATE-tailored_profile.json")
    create(:profile_document, status: "processing", file_type: "json", original_filename: "tailored.json").tap do |doc|
      ProfileJsonParserService.new(doc, path.to_s).parse
      doc.reload.update_columns(status: "completed")
      resolved = JSON.parse(OscalResolvedProfileCatalogService.new(doc.reload).export)
      doc.update!(resolved_catalog_json: resolved, lifecycle_status: "published")
    end
  end

  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) { SspFromProfileService.new(profile, authorization_boundary: boundary).create }
  def control(id) = ssp.ssp_controls.find_by(control_id: id)
  def item(control_id, statement_id) = control(control_id).ssp_control_statements.find_by(statement_id: statement_id)

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(create(:user, :admin))
  end

  def page
    get ssp_document_path(ssp)
    Nokogiri::HTML(response.body)
  end

  def edit_form(control_id) = page.at_css("#edit-#{control(control_id).id}")

  describe "which items take input" do
    # The owner's example: d. ("Specify:"), h. and i. are lead-ins; d.1–3, h.1–3
    # and i.1–3 are what an assessor tests and what takes input.
    it "gives ac-2 eighteen answerable items, with d., h. and i. as headings" do
      form = edit_form("ac-2")
      answerable = form.css("[data-part-response]").map { _1["data-part-response"] }

      expect(answerable.size).to eq(18)
      expect(answerable).to include("ac-2_smt.d.1", "ac-2_smt.h.3", "ac-2_smt.i.2", "ac-2_smt.l")
      %w[ac-2_smt.d ac-2_smt.h ac-2_smt.i].each do |lead_in|
        expect(answerable).not_to include(lead_in)
        expect(form.at_css("[data-lead-in='#{lead_in}']")).to be_present, lead_in
      end
    end

    it "gives an enhancement its own item with every field" do
      block = edit_form("ac-2.1").at_css("[data-part-response='ac-2.1_smt']")
      expect(block.css("select, textarea, input").map { _1["name"] }.compact.uniq.size).to eq(6)
    end
  end

  describe "SP 800-53A objectives" do
    let(:text) { ControlRequirementText.for_profile(profile).for_control("ac-1") }

    it "places each assessable objective under the item it tests, by NIST's ids" do
      expect(text.objectives_for("ac-1_smt.a.1.a").map(&:label)).to eq((1..7).map { "AC-01a.01(a)[0#{_1}]" })
      expect(text.objectives_for("ac-1_smt.a").map(&:label)).to eq((1..4).map { "AC-01a.[0#{_1}]" })
      expect(text.objectives_for("ac-1_smt.a.2")).to be_empty
      expect(text.objectives.values.sum(&:size)).to eq(17)
    end

    it "fills the baseline's parameter values into the objective" do
      prose = text.objectives_for("ac-1_smt.a.1.a").first.prose
      expect(prose).not_to include("{{ insert: param")
    end

    it "maps an objective id onto the nearest statement item" do
      ids = %w[ac-1_smt ac-1_smt.a ac-1_smt.a.1 ac-1_smt.a.1.a ac-2.1_smt].to_set
      expect(ControlRequirementText.statement_for_objective("ac-1_obj.a.1.a-3", ids)).to eq("ac-1_smt.a.1.a")
      expect(ControlRequirementText.statement_for_objective("ac-1_obj.a-3", ids)).to eq("ac-1_smt.a")
      expect(ControlRequirementText.statement_for_objective("ac-2.1_obj", ids)).to eq("ac-2.1_smt")
      expect(ControlRequirementText.statement_for_objective("ac-1_obj.c.2-1", ids)).to eq("ac-1_smt")
      expect(ControlRequirementText.statement_for_objective("not-an-objective", ids)).to be_nil
    end

    it "lists them under the item in the Edit form, with the assessor's latest determination read-only" do
      sar = SarFromSspService.new(ssp.tap { _1.update_columns(status: "completed") }).create
      sar.sar_controls.find_by(control_id: "ac-1").sar_control_objectives
         .find_by(objective_id: "ac-1_obj.a.1.a-2").update!(status: "failed")

      block = edit_form("ac-1").at_css("[data-part-response='ac-1_smt.a.1.a']")
      listed = block.css("[data-objective-id]")
      expect(listed.map { _1["data-objective-id"] }).to eq((1..7).map { "ac-1_obj.a.1.a-#{_1}" })
      expect(block.at_css("[data-objective-id='ac-1_obj.a.1.a-2']").text).to include("Assessor: failed")
      expect(block.css("[data-objective-id] input, [data-objective-id] select")).to be_empty

      lead_in = edit_form("ac-1").at_css("[data-lead-in='ac-1_smt.a']")
      expect(lead_in.css("[data-objective-id]").size).to eq(4)
    end
  end

  describe "the control's summary" do
    it "counts its items' statuses and calls a partly inherited control hybrid" do
      item("ac-2", "ac-2_smt.a").update!(implementation_status: "implemented", control_origination: %w[system-specific])
      item("ac-2", "ac-2_smt.b").update!(implementation_status: "planned", control_origination: %w[inherited])

      summary = SspResponseProgress.new(ssp).items_for("ac-2")
      expect(summary.to_s).to eq("1 of 18 implemented · 1 planned · 16 not set · hybrid")
      expect(summary.headline_label).to eq("Partial")
      expect(page.css("[data-testid='control-item-summary']").map(&:text)).to include(summary.to_s)
    end

    it "is fully inherited only when every item is" do
      ac21 = item("ac-2.1", "ac-2.1_smt")
      ac21.update!(control_origination: %w[inherited])
      summary = SspResponseProgress.new(ssp).items_for("ac-2.1")
      expect(summary).to be_fully_inherited
      expect(summary).not_to be_hybrid
      expect(summary.to_s).to end_with("inherited")
    end

    # One count per control, by the status its items add up to, so a cell's
    # count is the number of cards its filter shows; compliance counts items.
    it "counts the heatmap per control, by its items, and compliance per item" do
      item("ac-2.1", "ac-2.1_smt").update!(implementation_status: "implemented")
      item("ac-2", "ac-2_smt.a").update!(implementation_status: "implemented")

      html = page
      cell = html.at_css("[data-heatmap-target='badge'][data-family='AC'][data-status='Implemented']")
      expect(cell.text.strip).to eq("1")
      expect(html.css(".control-card[data-status='Implemented']").map { _1.at_css(".sparc-ctrl-id").text.strip })
        .to eq([ "ac-2.1" ])
      items = SspResponseProgress.new(ssp).items
      expect(html.at_css(".sparc-score").text.strip).to eq("#{(2 * 100.0 / items.size).round(1)}%")
    end
  end

  describe "round trip through OSCAL" do
    it "exports each item's fields and imports them back onto the same items" do
      roles = ssp.declared_role_ids
      item("ac-2", "ac-2_smt.d.1").update!(implementation_prose: "Users are listed in the IdP.",
                                           implementation_status: "planned",
                                           control_origination: %w[inherited system-specific],
                                           responsible_roles_data: [ { "role-id" => roles.first } ],
                                           expected_completion: Date.new(2027, 1, 15),
                                           remarks: "Waiting on the IdP migration.")
      json = OscalSspExportService.new(ssp.reload).export_unvalidated

      imported = create(:ssp_document, status: "processing", file_type: "json")
      Tempfile.create([ "ssp", ".json" ]) do |file|
        file.write(json.sub(ssp.uuid, SecureRandom.uuid).gsub(/"uuid": ?"[0-9a-f-]{36}"/) { %("uuid":"#{SecureRandom.uuid}") })
        file.flush
        SspJsonParserService.new(imported, file.path).parse
      end

      back = imported.ssp_controls.find_by(control_id: "ac-2").ssp_control_statements.find_by(statement_id: "ac-2_smt.d.1")
      expect(back).to have_attributes(implementation_status: "planned",
                                      control_origination: %w[system-specific inherited],
                                      expected_completion: Date.new(2027, 1, 15),
                                      remarks: "Waiting on the IdP migration.")
      expect(back.responsible_roles_data).to eq([ { "role-id" => roles.first } ])
      expect(imported.ssp_controls.find_by(control_id: "ac-2").ssp_control_fields
                     .where(field_name: SspControlField::RETIRED_FIELDS)).to be_empty
    end
  end

  describe "the assessment plan" do
    it "shows, under each objective, the SSP item it tests and what that item records" do
      item("ac-1", "ac-1_smt.a.1.a").update!(implementation_status: "planned", control_origination: %w[inherited])
      sap = SapGeneratorService.new(name: "Plan", ssp_document: ssp).generate

      get sap_document_path(sap)
      html = Nokogiri::HTML(response.body)
      row = html.at_css("tr[data-objective-id='ac-1_obj.a.1.a-1']")
      expect(row.at_css("[data-testid='ssp-item-for-objective']").text.squish).to include("Planned · Inherited")
      expect(sap.sap_controls.find_by(control_id: "ac-1").sap_control_fields
                .find_by(field_name: "implementation_status").field_value).to start_with("0 of 6 implemented · 1 planned")
    end
  end
end
