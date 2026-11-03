# frozen_string_literal: true

require "rails_helper"

# #1328 — on an SSP whose controls hold only `<control>_smt`, Edit offered only
# Notes while the badge counted the items ("0/3 answered"). Opening the SSP now
# gives every counted item its row, and the author answers it as on any SSP.
RSpec.describe "SSP items for an SSP in the old shape (#1328)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog) }
  let!(:catalog_control) do
    create(:catalog_control, control_family: family, control_id: "ac-1").tap do |cc|
      [ [ "ac-1_smt", nil, nil ], [ "ac-1_smt.a", "ac-1_smt", "a." ], [ "ac-1_smt.a.1", "ac-1_smt.a", "1." ],
        [ "ac-1_smt.a.2", "ac-1_smt.a", "2." ], [ "ac-1_smt.b", "ac-1_smt", "b." ] ].each_with_index do |(pid, parent, label), i|
        cc.catalog_control_parts.create!(part_id: pid, parent_part_id: parent, label: label, row_order: i,
                                         part_name: pid == "ac-1_smt" ? "statement" : "item",
                                         prose: "prose #{pid}", uuid: SecureRandom.uuid)
      end
    end
  end

  let(:boundary) { create(:authorization_boundary) }
  # A resolved baseline with NO catalog link: the customer's shape.
  let(:profile) do
    create(:profile_document, control_catalog: nil, lifecycle_status: "published",
                              resolved_catalog_json: { "catalog" => { "controls" => [] } })
      .tap { create(:profile_control, profile_document: _1, control_id: "ac-1") }
  end
  let(:ssp) do
    create(:ssp_document, authorization_boundary: boundary, profile_document: profile, status: "completed")
  end
  let!(:control) do
    ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy").tap do |c|
      c.ssp_control_statements.create!(statement_id: "ac-1_smt", uuid: SecureRandom.uuid)
    end
  end
  let(:writer) do
    create(:user).tap do |u|
      grant_permission(u, "ssp.read", authorization_boundary: boundary)
      grant_permission(u, "ssp.write", authorization_boundary: boundary)
    end
  end

  def edit_form = Nokogiri::HTML(response.body).at_css("#edit-#{control.id}")

  def answer_boxes = edit_form.css("textarea[name$='[implementation_prose]']")

  it "offers every item the badge counts in Edit, not only Notes" do
    sign_in_as(writer)
    get ssp_document_path(ssp)

    expect(response).to have_http_status(:ok)
    expect(edit_form.at_css("[data-testid=part-responses]")).to be_present
    expect(answer_boxes.size).to eq(3)
    expect(control.ssp_control_statements.reload.pluck(:statement_id))
      .to match_array(%w[ac-1_smt ac-1_smt.a ac-1_smt.a.1 ac-1_smt.a.2 ac-1_smt.b])
  end

  it "saves an answer to one of those items" do
    sign_in_as(writer)
    get ssp_document_path(ssp)
    item = control.ssp_control_statements.find_by(statement_id: "ac-1_smt.a.1")

    patch ssp_document_path(ssp), params: {
      control_id: "ac-1",
      statements: { item.id.to_s => { implementation_prose: "We publish the policy.", implementation_status: "implemented" } }
    }

    expect(response).to have_http_status(:found)
    expect(item.reload).to have_attributes(implementation_prose: "We publish the policy.", implementation_status: "implemented")
  end

  it "adds nothing when the SSP already has every row" do
    sign_in_as(writer)
    get ssp_document_path(ssp)

    expect { get ssp_document_path(ssp) }.not_to change { SspControlStatement.count }
  end
end
