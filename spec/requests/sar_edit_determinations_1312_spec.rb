# frozen_string_literal: true

require "rails_helper"

# #1312 (owner testing) — the SAR had the SSP's problem: a control's Edit held
# only control-level fields, and each 800-53A objective was determined
# elsewhere, one at a time, through a per-row Edit and a modal. The control's
# Edit now records every objective's determination and notes in its one Save,
# with the SSP item each objective tests beside it.
RSpec.describe "Determining a SAR control's objectives from its Edit form", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) { create(:ssp_document, status: "completed", authorization_boundary: boundary) }
  let(:sar) { create(:sar_document, status: "completed", ssp_document: ssp, authorization_boundary: boundary) }
  let!(:result) { sar.sar_results.create!(uuid: SecureRandom.uuid, title: "Results", description: "r", start_time: Time.current) }
  let(:control) { sar.sar_controls.create!(control_id: "ac-1", title: "Policy", row_order: 0) }
  let!(:group) { control.sar_control_objectives.create!(objective_id: "ac-1_obj.a", label: "AC-01a.", uuid: SecureRandom.uuid, status: "pending", row_order: 0) }
  let!(:first) do
    control.sar_control_objectives.create!(objective_id: "ac-1_obj.a-1", label: "AC-01a.[01]", uuid: SecureRandom.uuid,
                                           prose: "a policy is developed", parent_objective_id: "ac-1_obj.a", status: "pending", row_order: 1)
  end
  let!(:second) do
    control.sar_control_objectives.create!(objective_id: "ac-1_obj.a-2", label: "AC-01a.[02]", uuid: SecureRandom.uuid,
                                           prose: "the policy is disseminated", parent_objective_id: "ac-1_obj.a", status: "pending", row_order: 2)
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(create(:user, :admin))
    ssp_control = ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy")
    ssp_control.ssp_control_statements.create!(statement_id: "ac-1_smt.a", label: "a.", uuid: SecureRandom.uuid,
                                               implementation_prose: "Policy POL-AC-1 is published.",
                                               implementation_status: "implemented")
  end

  def edit_form
    get sar_document_path(sar)
    Nokogiri::HTML(response.body).at_css("#edit-#{control.id}")
  end

  it "offers each assessable objective in the Edit form, with the SSP's claim beside it" do
    form = edit_form
    blocks = form.css("[data-objective-determination]")

    expect(blocks.map { _1["data-objective-determination"] }).to eq(%w[ac-1_obj.a-1 ac-1_obj.a-2])
    expect(form.at_css("[data-objective-group='ac-1_obj.a']").css("select, textarea")).to be_empty
    claim = blocks.first.at_css("[data-testid='ssp-claim']").text.squish
    expect(claim).to include("Policy POL-AC-1 is published.", "Implemented")
    statuses = blocks.first.css("select[name='objectives[#{first.id}][status]'] option").map { _1["value"] }
    expect(statuses).to eq(SarControlObjective::OBJECTIVE_STATUSES)
  end

  it "saves every determination in one Save, and a failure opens the control's risk" do
    patch sar_document_path(sar), params: {
      sar_control_id: control.id,
      fields: { "assessor" => "A. Assessor" },
      objectives: { first.id => { status: "passing", assessor_notes: "Examined POL-AC-1." },
                    second.id => { status: "failed", assessor_notes: "Not on the intranet." } }
    }

    expect(flash[:success]).to include("2 determinations saved")
    expect(first.reload).to have_attributes(status: "passing", assessor_notes: "Examined POL-AC-1.", assessor_name: "A. Assessor")
    expect(second.reload.status).to eq("failed")
    expect(second.assessed_at).to be_present
    risk = result.sar_risks.find_by(title: "Risk for ac-1")
    expect(risk&.status).to eq("open")
  end

  it "leaves an objective submitted unchanged alone" do
    patch sar_document_path(sar), params: { sar_control_id: control.id,
                                            objectives: { first.id => { status: "pending", assessor_notes: "" } } }
    expect(first.reload).to have_attributes(status: "pending", assessor_name: nil)
  end

  it "refuses an objective from another control, and saves nothing" do
    other = sar.sar_controls.create!(control_id: "ac-2", title: "Accounts", row_order: 1)
    stray = other.sar_control_objectives.create!(objective_id: "ac-2_obj.a-1", uuid: SecureRandom.uuid, prose: "x", status: "pending")

    patch sar_document_path(sar), params: { sar_control_id: control.id,
                                            objectives: { first.id => { status: "passing" }, stray.id => { status: "failed" } } }

    expect(flash[:error]).to be_present
    expect(first.reload.status).to eq("pending")
    expect(stray.reload.status).to eq("pending")
  end

  it "keeps the read view read-only" do
    get sar_document_path(sar)
    table = Nokogiri::HTML(response.body).at_css("#view-#{control.id}")
    expect(table.css("tr[data-objective-id] a, tr[data-objective-id] button")).to be_empty
  end
end
