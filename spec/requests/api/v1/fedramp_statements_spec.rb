# frozen_string_literal: true

require "rails_helper"

# #1390 — GET/PUT /api/v1/authorization_boundaries/:id/fedramp_statements.
RSpec.describe "API v1 FedRAMP statements", type: :request do
  let(:boundary) { create(:authorization_boundary, :fedramp) }
  let(:base) { "/api/v1/authorization_boundaries/#{boundary.id}/fedramp_statements" }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  def user_with(permissions, on: boundary)
    user = create(:user)
    role = create(:role, :authorization_boundary_scoped, permissions: permissions)
    create(:user_role, user: user, role: role, authorization_boundary_id: on.id)
    user
  end

  let(:reader) { user_with({ "evidence.read" => true }) }
  let(:writer) { user_with({ "evidence.read" => true, "evidence.write" => true }) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  it "401s without a token" do
    get base
    expect(response).to have_http_status(:unauthorized)
  end

  it "lists the applicable rules with the profile, answered or not" do
    boundary.fedramp_statements.create!(kind: "frr", rule_id: "SDR-CSO-FRR", status: "Implemented")
    get base, headers: headers_for(reader)
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["meta"]).to include("kind" => "frr", "certification_type" => "20x", "certification_path" => "Program",
                                    "certification_class" => "B", "sdr_version" => 1, "answered" => 1,
                                    "total" => boundary.fedramp_applicable_rules.size)
    sdr = body["data"].find { |r| r["rule_id"] == "SDR-CSO-FRR" }
    expect(sdr).to include("family" => "SDR", "force" => "MUST")
    expect(sdr.dig("answer", "status")).to eq("Implemented")
    expect(body["data"].find { |r| r["rule_id"] == "VER-RPT-VDT" }["answer"]).to be_nil
  end

  it "lists the KSIs" do
    get base, params: { kind: "ksi" }, headers: headers_for(reader)
    expect(response.parsed_body["meta"]["total"]).to eq(46)
    expect(response.parsed_body["data"].first).to include("theme", "controls")
  end

  it "records a statement (201, then 200), changing only the fields sent, and audits it" do
    path = "#{base}/ksi/KSI-CED-RAT"
    expect {
      put path, params: { fedramp_statement: { status: "Partially Implemented", tests: [ "quarterly" ] } },
                headers: headers_for(writer), as: :json
    }.to change { AuditEvent.where(action: "fedramp_statement_recorded").count }.by(1)
    expect(response).to have_http_status(:created)

    put path, params: { fedramp_statement: { implementation: "Training is reviewed." } }, headers: headers_for(writer), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "answer")).to include("status" => "Partially Implemented",
                                                                  "tests" => [ "quarterly" ],
                                                                  "implementation" => "Training is reviewed.")
    get path, headers: headers_for(reader)
    expect(response.parsed_body.dig("data", "answer", "implementation")).to eq("Training is reviewed.")
  end

  it "422s for a rule that does not apply, a status the schema lacks, or an unknown field" do
    put "#{base}/frr/FRC-CSF-BSL", params: { fedramp_statement: { status: "Implemented" } }, headers: headers_for(writer), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to include("does not apply")

    put "#{base}/frr/SDR-CSO-FRR", params: { fedramp_statement: { status: "Done" } }, headers: headers_for(writer), as: :json
    expect(response).to have_http_status(:unprocessable_content)

    put "#{base}/frr/SDR-CSO-FRR", params: { fedramp_statement: { owner: "x" } }, headers: headers_for(writer), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(boundary.fedramp_statements).to be_empty
  end

  it "401s before it reads the path, and 422s an unknown kind once authenticated" do
    get "#{base}/nope/NOT-A-RULE"
    expect(response).to have_http_status(:unauthorized)
    get "#{base}/nope/SDR-CSO-FRR", headers: headers_for(reader)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to include("kind must be one of")
  end

  it "403s a reader on PUT and a stranger on GET" do
    put "#{base}/frr/SDR-CSO-FRR", params: { fedramp_statement: { status: "Implemented" } }, headers: headers_for(reader), as: :json
    expect(response).to have_http_status(:forbidden)
    get base, headers: headers_for(user_with({ "evidence.read" => true }, on: create(:authorization_boundary)))
    expect(response).to have_http_status(:forbidden)
  end

  it "422s while FedRAMP is off for the boundary" do
    boundary.update!(fedramp_enabled: false)
    get base, headers: headers_for(reader)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to include("FedRAMP is not enabled")
  end

  it "also gates the FedRAMP reports and evaluations while FedRAMP is off" do
    boundary.update!(fedramp_enabled: false, fedramp_package_overview_uri: "https://provider.example/cpo.json")
    admin = headers_for(create(:user, :admin))
    get "/api/v1/authorization_boundaries/#{boundary.id}/fedramp/vulnerability_detail_report", headers: admin
    expect(response).to have_http_status(:unprocessable_content)
    get "/api/v1/authorization_boundaries/#{boundary.id}/fedramp_evaluations", headers: admin
    expect(response).to have_http_status(:unprocessable_content)
  end
end
