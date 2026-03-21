# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Service Account API Auth Enforcement", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:api_auth_mode).and_return("local")
  end

  let(:owner) { create(:user) }
  let(:service_account) { create(:user, service_account: true, owner: owner) }

  describe "endpoint scoping" do
    it "allows requests to permitted endpoints" do
      token = ApiToken.generate!(
        user: service_account,
        name: "scoped",
        allowed_endpoints: [ "/api/v1/available" ]
      )
      get "/api/v1/available", headers: { "Authorization" => "Bearer #{token.plaintext_token}" }
      expect(response).to have_http_status(:ok)
    end

    it "blocks requests to non-permitted endpoints" do
      token = ApiToken.generate!(
        user: service_account,
        name: "scoped",
        allowed_endpoints: [ "/api/v1/ssp_documents" ]
      )
      get "/api/v1/available", headers: { "Authorization" => "Bearer #{token.plaintext_token}" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("not authorized for this endpoint")
    end

    it "allows wildcard endpoint patterns" do
      token = ApiToken.generate!(
        user: service_account,
        name: "wildcard",
        allowed_endpoints: [ "/api/v1/*" ]
      )
      get "/api/v1/available", headers: { "Authorization" => "Bearer #{token.plaintext_token}" }
      expect(response).to have_http_status(:ok)
    end

    it "allows all endpoints when allowed_endpoints is empty" do
      token = ApiToken.generate!(
        user: service_account,
        name: "unrestricted",
        allowed_endpoints: []
      )
      get "/api/v1/available", headers: { "Authorization" => "Bearer #{token.plaintext_token}" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "CIDR enforcement" do
    it "blocks requests from non-allowed IPs" do
      token = ApiToken.generate!(
        user: service_account,
        name: "cidr-scoped",
        allowed_cidrs: [ "10.0.0.0/8" ]
      )
      get "/api/v1/available", headers: { "Authorization" => "Bearer #{token.plaintext_token}" }
      # Test request comes from 127.0.0.1 which is not in 10.0.0.0/8
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("CIDR")
    end

    it "allows requests from permitted CIDRs" do
      token = ApiToken.generate!(
        user: service_account,
        name: "cidr-scoped",
        allowed_cidrs: [ "127.0.0.0/8" ]
      )
      get "/api/v1/available", headers: { "Authorization" => "Bearer #{token.plaintext_token}" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "sparc_sa_ token prefix" do
    it "generates tokens with sparc_sa_ prefix for service accounts" do
      token = ApiToken.generate!(user: service_account, name: "test")
      expect(token.plaintext_token).to start_with("sparc_sa_")
    end

    it "generates tokens with sparc_ prefix for regular users" do
      regular_user = create(:user)
      token = ApiToken.generate!(user: regular_user, name: "test")
      expect(token.plaintext_token).to start_with("sparc_")
      expect(token.plaintext_token).not_to start_with("sparc_sa_")
    end
  end
end
