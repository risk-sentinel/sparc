# frozen_string_literal: true

require "rails_helper"

# Per-objective determinations through the API, and the risk they keep in step.
#
# Recording a result was web-only, and a failed objective changed nothing but
# its own status. The POA&M is built from SAR risks, so an assessed failure
# never reached it.
RSpec.describe "Api::V1::SarObjectives", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:document) { create(:sar_document, authorization_boundary: boundary) }
  let!(:result)  { create(:sar_result, sar_document: document) }
  let(:control)  { create(:sar_control, sar_document: document, control_id: "ac-1") }
  let!(:first)   { create(:sar_control_objective, sar_control: control, objective_id: "ac-1_obj.a-1", prose: "a policy is developed;") }
  let!(:second)  { create(:sar_control_objective, sar_control: control, objective_id: "ac-1_obj.a-2", prose: "a policy is documented;") }
  let(:admin)    { create(:user, :admin) }
  let(:headers)  { { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'T').plaintext_token}" } }
  let(:path)     { "/api/v1/sar_documents/#{document.slug}/objectives" }

  def determine(objective_id, status, as: headers)
    patch "#{path}/#{objective_id}", params: { sar_control_objective: { status: status } }, headers: as, as: :json
  end

  def control_risk = result.sar_risks.find_by(title: "Risk for ac-1")

  it "lists the document's objectives in the collection envelope" do
    get path, headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["data"].map { |o| o["objective_id"] }).to eq(%w[ac-1_obj.a-1 ac-1_obj.a-2])
    expect(body["meta"]["count"]).to eq(2)
  end

  it "opens the control's risk when an objective fails, and the POA&M carries it" do
    determine("ac-1_obj.a-1", "failed")

    expect(response).to have_http_status(:ok)
    expect(first.reload.status).to eq("failed")
    expect(first.assessed_at).to be_present
    expect(control_risk.status).to eq("open")
    expect(control_risk.statement).to include("a policy is developed;")
    expect(control_risk.sar_findings.map { |f| f.target_data["target-id"] }).to eq([ "ac-1_obj.a-1" ])

    poam = PoamGeneratorService.new(name: "POA&M", sar_document: document.reload,
                                    authorization_boundary: boundary).generate
    expect(poam.poam_document.poam_items.pluck(:title)).to eq([ "Risk for ac-1" ])
  end

  it "keeps one risk per control however many objectives fail" do
    determine("ac-1_obj.a-1", "failed")
    determine("ac-1_obj.a-2", "failed")

    expect(result.sar_risks.where(title: "Risk for ac-1").count).to eq(1)
    expect(control_risk.sar_findings.count).to eq(2)
  end

  it "closes the risk once no objective of the control is failing, and the POA&M drops it" do
    determine("ac-1_obj.a-1", "failed")
    determine("ac-1_obj.a-1", "passing")

    expect(control_risk.status).to eq("closed")
    poam = PoamGeneratorService.new(name: "POA&M", sar_document: document.reload,
                                    authorization_boundary: boundary).generate
    expect(poam.poam_document.poam_items).to be_empty
  end

  it "creates no risk for a passing objective" do
    determine("ac-1_obj.a-1", "passing")

    expect(control_risk).to be_nil
  end

  it "accepts the record id" do
    patch "#{path}/#{second.id}", params: { sar_control_objective: { assessor_name: "J. Assessor" } },
                                  headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(second.reload.assessor_name).to eq("J. Assessor")
  end

  it "refuses a status that is not a determination" do
    determine("ac-1_obj.a-1", "probably-fine")

    expect(response).to have_http_status(:unprocessable_content)
    expect(first.reload.status).to eq("pending")
  end

  context "a non-admin holding sar.write on the boundary" do
    let(:writer) do
      grant_permission(create(:user), "sar.write", authorization_boundary: boundary).tap do |user|
        grant_permission(user, "sar.read", authorization_boundary: boundary)
      end
    end

    it "may record a determination" do
      determine("ac-1_obj.a-1", "failed", as: { "Authorization" => "Bearer #{ApiToken.generate!(user: writer, name: 'W').plaintext_token}" })

      expect(response).to have_http_status(:ok)
    end
  end

  context "a non-admin with only sar.read" do
    let(:reader) { grant_permission(create(:user), "sar.read", authorization_boundary: boundary) }
    let(:reader_headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: reader, name: 'R').plaintext_token}" } }

    it "may list but not record" do
      get path, headers: reader_headers
      expect(response).to have_http_status(:ok)

      determine("ac-1_obj.a-1", "failed", as: reader_headers)
      expect(response).to have_http_status(:forbidden)
      expect(first.reload.status).to eq("pending")
    end
  end
end
