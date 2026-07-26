# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Aggregations", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  let(:boundary) { create(:authorization_boundary) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def path = api_v1_authorization_boundary_aggregate_path(boundary)

  it "aggregates synchronously and returns the per-document summary" do
    post path, headers: admin_headers
    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)["data"]
    expect(data["status"]).to eq("aggregated")
    expect(data).to include("ssp", "sar", "sap", "poam")
  end

  it "enqueues the job with ?async=true" do
    expect {
      post path, params: { async: "true" }, headers: admin_headers
    }.to have_enqueued_job(AggregateFindingsJob).with(boundary.id)
    expect(response).to have_http_status(:accepted)
  end

  it "forbids a member without evidence.write" do
    post path, headers: member_headers
    expect(response).to have_http_status(:forbidden)
  end

  it "401 without a token" do
    post path
    expect(response).to have_http_status(:unauthorized)
  end
end
