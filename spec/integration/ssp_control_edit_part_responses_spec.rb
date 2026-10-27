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

  it "saves every answered part and the control's notes in one Save, leaving an untouched box alone" do
    patch ssp_document_path(ssp), params: {
      control_id: "ac-1",
      fields: { "notes" => "Reviewed with the ISSO." },
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
    expect(ac1.ssp_control_fields.find_by(field_name: "notes").field_value).to eq("Reviewed with the ISSO.")
  end

  # #1312 — every item that takes a response sets all of its own fields, and
  # the form is submitted as the page renders it: each input's own name.
  it "saves each item's status, origination, roles, completion and remarks, as the form renders them" do
    form = edit_form
    item = part("ac-1_smt.c.2")
    block = form.at_css("[data-part-response='ac-1_smt.c.2']")
    names = block.css("textarea, select, input").map { _1["name"] }.uniq
    prefix = "statements[#{item.id}]"
    expect(names).to include("#{prefix}[implementation_prose]", "#{prefix}[implementation_status]",
                             "#{prefix}[control_origination][]", "#{prefix}[responsible_role_ids][]",
                             "#{prefix}[expected_completion]", "#{prefix}[remarks]")
    expect(block.css("select[name='#{prefix}[implementation_status]'] option").map { _1["value"] }.compact_blank)
      .to eq(%w[implemented partial planned alternative not-applicable])
    expect(block.css("input[name='#{prefix}[control_origination][]'][type=checkbox]").map { _1["value"] })
      .to eq(%w[organization system-specific customer-configured customer-provided inherited])
    role = ssp.declared_role_ids.first
    expect(block.css("select[name='#{prefix}[responsible_role_ids][]'] option").map { _1["value"] }).to include(role)

    patch ssp_document_path(ssp), params: {
      control_id: "ac-1",
      statements: { item.id => { implementation_prose: "Procedures are reviewed annually.",
                                 implementation_status: "partial",
                                 control_origination: [ "", "inherited", "system-specific" ],
                                 responsible_role_ids: [ "", role ],
                                 expected_completion: "2027-06-30", remarks: "The provider reviews its share." } }
    }

    item.reload
    expect(item.implementation_status).to eq("partial")
    expect(item.control_origination).to eq(%w[system-specific inherited])
    expect(item).to be_partially_inherited
    expect(item.responsible_roles_data).to eq([ { "role-id" => role } ])
    expect(item.expected_completion).to eq(Date.new(2027, 6, 30))
    expect(item.remarks).to eq("The provider reviews its share.")

    # Unchecking everything clears it: the hidden "" still sends the field.
    patch ssp_document_path(ssp), params: {
      control_id: "ac-1",
      statements: { item.id => { control_origination: [ "" ], responsible_role_ids: [ "" ], implementation_status: "" } }
    }
    item.reload
    expect(item.control_origination).to eq([])
    expect(item.responsible_roles_data).to eq([])
    expect(item.implementation_status).to be_nil
  end

  it "shows a lead-in as a heading with no inputs" do
    form = edit_form
    lead_in = form.at_css("[data-lead-in='ac-1_smt.a.1']")

    expect(lead_in).to be_present
    expect(lead_in.css("textarea, select, input")).to be_empty
    expect(form.at_css("[data-part-response='ac-1_smt.a.1']")).to be_nil
  end

  it "refuses a role the document does not declare, and saves nothing" do
    item = part("ac-1_smt.b")
    patch ssp_document_path(ssp), params: {
      control_id: "ac-1",
      statements: { item.id => { implementation_status: "implemented", responsible_role_ids: [ "nobody-declared-this" ] } }
    }

    expect(flash[:error]).to include("not declared")
    expect(item.reload.implementation_status).to be_nil
  end

  it "refuses a part from another control, and saves nothing" do
    other = ssp.ssp_controls.find_by(control_id: "ac-2").ssp_control_statements.first

    patch ssp_document_path(ssp), params: {
      control_id: "ac-1", fields: { "notes" => "kept?" },
      statements: { part("ac-1_smt.b").id => { implementation_prose: "kept?" }, other.id => { implementation_prose: "wrong control" } }
    }

    expect(flash[:error]).to be_present
    expect(part("ac-1_smt.b").implementation_prose).to be_nil
    expect(other.reload.implementation_prose).to be_nil
    expect(ac1.ssp_control_fields.find_by(field_name: "notes")&.field_value).to be_blank
  end
end
