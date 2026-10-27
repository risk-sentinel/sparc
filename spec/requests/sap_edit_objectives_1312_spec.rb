# frozen_string_literal: true

require "rails_helper"

# #1312 (owner testing) — the SAP, like the SSP and SAR, planned each 800-53A
# objective one at a time through a per-row Edit and its own modal. The
# control's Edit now sets every objective's status and notes in its one Save,
# with the SSP item each objective tests beside it.
RSpec.describe "Planning a SAP control's objectives from its Edit", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) { create(:ssp_document, status: "completed", authorization_boundary: boundary) }
  let(:sap) { create(:sap_document, status: "completed", ssp_document: ssp, authorization_boundary: boundary) }
  let(:control) { sap.sap_controls.create!(control_id: "ac-1", title: "Policy", row_order: 0) }
  let!(:group) { control.sap_control_objectives.create!(objective_id: "ac-1_obj.a", label: "AC-01a.", uuid: SecureRandom.uuid, status: "pending", row_order: 0) }
  let!(:first) do
    control.sap_control_objectives.create!(objective_id: "ac-1_obj.a-1", label: "AC-01a.[01]", uuid: SecureRandom.uuid,
                                           prose: "a policy is developed", parent_objective_id: "ac-1_obj.a", status: "pending", row_order: 1)
  end
  let!(:second) do
    control.sap_control_objectives.create!(objective_id: "ac-1_obj.a-2", label: "AC-01a.[02]", uuid: SecureRandom.uuid,
                                           prose: "the policy is disseminated", parent_objective_id: "ac-1_obj.a", status: "pending", row_order: 2)
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(create(:user, :admin))
    ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy")
       .ssp_control_statements.create!(statement_id: "ac-1_smt.a", label: "a.", uuid: SecureRandom.uuid,
                                       implementation_status: "planned", control_origination: %w[inherited])
  end

  it "offers each objective in the control's Edit, with the SSP item it tests" do
    get sap_document_path(sap, control_id: control.id)
    modal = Nokogiri::HTML(response.body).at_css("#editModal")

    blocks = modal.css("[data-objective-plan]")
    expect(blocks.map { _1["data-objective-plan"] }).to eq(%w[ac-1_obj.a-1 ac-1_obj.a-2])
    expect(modal.at_css("[data-objective-group='ac-1_obj.a']").css("select, textarea")).to be_empty
    expect(blocks.first.at_css("[data-testid='ssp-claim']").text.squish).to include("Planned · Inherited")
    expect(blocks.first.css("select[name='objectives[#{first.id}][status]'] option").map { _1["value"] })
      .to eq(SapControlObjective::OBJECTIVE_STATUSES)
  end

  it "saves the control and every objective in one Save" do
    patch sap_document_path(sap, control_id: control.id), params: {
      sap_control: { assessor_name: "A. Assessor", assessment_methods: %w[examine] },
      objectives: { first.id => { status: "in-progress", assessor_notes: "Examine POL-AC-1." },
                    second.id => { status: "pending", assessor_notes: "" } }
    }

    expect(flash[:success]).to include("1 objective saved")
    expect(first.reload).to have_attributes(status: "in-progress", assessor_notes: "Examine POL-AC-1.", assessor_name: "A. Assessor")
    expect(second.reload).to have_attributes(status: "pending", assessor_name: nil)
    expect(control.reload.assessment_method).to eq("examine")
  end

  it "refuses an objective from another control, and saves nothing" do
    other = sap.sap_controls.create!(control_id: "ac-2", title: "Accounts", row_order: 1)
    stray = other.sap_control_objectives.create!(objective_id: "ac-2_obj.a-1", uuid: SecureRandom.uuid, prose: "x", status: "pending")

    patch sap_document_path(sap, control_id: control.id), params: {
      sap_control: { assessor_name: "Changed" },
      objectives: { first.id => { status: "in-progress" }, stray.id => { status: "failed" } }
    }

    expect(flash[:error]).to include("not part of ac-1")
    expect(first.reload.status).to eq("pending")
    expect(stray.reload.status).to eq("pending")
    expect(control.reload.assessor_name).not_to eq("Changed")
  end

  it "keeps the objectives table read-only" do
    get sap_document_path(sap)
    rows = Nokogiri::HTML(response.body).css("tr[data-objective-id]")
    expect(rows).to be_present
    expect(rows.css("a, button")).to be_empty
  end
end
