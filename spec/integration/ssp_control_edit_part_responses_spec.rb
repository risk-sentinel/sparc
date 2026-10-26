# frozen_string_literal: true

require "rails_helper"

# A control's Edit opens a response box for every part the baseline requires,
# and its Save Changes stores them with the control's fields. Before, Edit
# offered only control-level fields, and each part was answered one row at a
# time with its own Edit and Save.
RSpec.describe "Answering a control's parts from its Edit form", type: :request do
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

  let(:ssp) { SspFromProfileService.new(profile, authorization_boundary: create(:authorization_boundary)).create }
  let(:ac1) { ssp.ssp_controls.find_by(control_id: "ac-1") }
  def part(statement_id) = ac1.ssp_control_statements.find_by(statement_id: statement_id)

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(create(:user, :admin))
  end

  def edit_form
    get ssp_document_path(ssp)
    Nokogiri::HTML(response.body).at_css("#edit-#{ac1.id}")
  end

  it "offers a box for each part the baseline requires, inside the control's own Save" do
    form = edit_form
    boxes = form.css("[data-testid='part-responses'] [data-part-response]")
    required = SspResponseProgress.new(ssp).then { |p| ac1.ssp_control_statements.count { |s| p.part_for_statement(s.id) } }

    expect(required).to be > 1
    expect(boxes.size).to eq(required)
    expect(boxes.map { |b| b["data-part-response"] }).to include("ac-1_smt.b")
    expect(form.at_css("[data-part-response='ac-1_smt.b']").text.squish).to include("Designate an Information System Security Manager (ISSM)")
    expect(form.at_css("form textarea[name='statements[#{part("ac-1_smt.b").id}][implementation_prose]']")).to be_present
  end

  it "saves every answered part and the control's fields in one Save, leaving an untouched box alone" do
    patch ssp_document_path(ssp), params: {
      control_id: "ac-1",
      fields: { "status" => "Implemented" },
      statements: {
        part("ac-1_smt.b").id => { implementation_prose: "The ISSM owns the access control policy." },
        part("ac-1_smt.c.1").id => { implementation_prose: "Reviewed every 365 days and after each significant change." },
        part("ac-1_smt.a.2").id => { implementation_prose: "" }
      }
    }

    expect(flash[:success]).to include("2 part responses saved")
    expect(part("ac-1_smt.b").implementation_prose).to eq("The ISSM owns the access control policy.")
    expect(part("ac-1_smt.c.1").implementation_prose).to start_with("Reviewed every 365 days")
    expect(part("ac-1_smt.a.2").implementation_prose).to be_nil
    expect(ac1.ssp_control_fields.find_by(field_name: "status").field_value).to eq("Implemented")
  end

  it "refuses a part from another control, and saves nothing" do
    other = ssp.ssp_controls.find_by(control_id: "ac-2").ssp_control_statements.first

    patch ssp_document_path(ssp), params: {
      control_id: "ac-1", fields: { "status" => "Implemented" },
      statements: { part("ac-1_smt.b").id => { implementation_prose: "kept?" }, other.id => { implementation_prose: "wrong control" } }
    }

    expect(flash[:error]).to be_present
    expect(part("ac-1_smt.b").implementation_prose).to be_nil
    expect(other.reload.implementation_prose).to be_nil
    expect(ac1.ssp_control_fields.find_by(field_name: "status").field_value).to be_blank
  end
end
