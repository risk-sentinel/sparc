# frozen_string_literal: true

require "rails_helper"

# #1015 — leveraged authorizations through the API.
#
# The authority model is MEMBERSHIP of the leveraging boundary, not
# `authorization_boundaries.write`. That mirrors the web controller
# deliberately (#919 memo: the one place membership and permission still
# disagree), so these specs pin membership — and pin it in both directions,
# since an allow-leg-only spec passes against an endpoint with no guard.
RSpec.describe "Api::V1::LeveragedAuthorizations", type: :request do
  let(:organization) { create(:organization) }
  let(:boundary)     { create(:authorization_boundary, organization: organization) }
  let(:leveraged)    { create(:authorization_boundary, organization: organization) }

  let(:admin)  { create(:user, :admin) }
  let(:member) { create(:user) }
  let(:outsider) { create(:user) }

  let(:role) { create(:role, :authorization_boundary_scoped, name: "isso-#{SecureRandom.hex(4)}") }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    create(:user_role, user: member, role: role, authorization_boundary: boundary)
  end

  let(:valid_attributes) do
    { name: "Leveraged PaaS", crm_type: "oscal_no_access", date_authorized: Date.current.iso8601,
      description: "Inherited controls from the platform ATO" }
  end

  describe "POST .../leveraged_authorizations" do
    it "creates the record for a boundary member, and an independent read confirms it" do
      expect {
        post api_v1_authorization_boundary_leveraged_authorizations_path(boundary),
          params: { leveraged_authorization: valid_attributes },
          headers: headers_for(member), as: :json
      }.to change { boundary.leveraging_relationships.count }.by(1)

      expect(response).to have_http_status(:created)
      created_id = response.parsed_body.dig("data", "id")

      get api_v1_authorization_boundary_leveraged_authorization_path(boundary, created_id),
        headers: headers_for(member)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data["name"]).to eq("Leveraged PaaS")
      expect(data["crm_type"]).to eq("oscal_no_access")
      expect(data["scenario"]).to eq(2)
      expect(data["description"]).to eq("Inherited controls from the platform ATO")
    end

    it "refuses a non-member, and creates nothing" do
      expect {
        post api_v1_authorization_boundary_leveraged_authorizations_path(boundary),
          params: { leveraged_authorization: valid_attributes },
          headers: headers_for(outsider), as: :json
      }.not_to change { boundary.leveraging_relationships.count }

      expect(response).to have_http_status(:forbidden)
    end

    it "allows an instance admin who is not a member" do
      post api_v1_authorization_boundary_leveraged_authorizations_path(boundary),
        params: { leveraged_authorization: valid_attributes },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:created)
    end

    it "refuses an unauthenticated caller" do
      post api_v1_authorization_boundary_leveraged_authorizations_path(boundary),
        params: { leveraged_authorization: valid_attributes }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # #988 — leveraging means relying on someone else's authorization, so a
    # record with no authorization date is a claim to inherit one that does not
    # exist. OSCAL requires date-authorized on every leveraged-authorization.
    it "refuses a record with no authorization date" do
      post api_v1_authorization_boundary_leveraged_authorizations_path(boundary),
        params: { leveraged_authorization: valid_attributes.except(:date_authorized) },
        headers: headers_for(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a crm_type outside the enumerated set" do
      post api_v1_authorization_boundary_leveraged_authorizations_path(boundary),
        params: { leveraged_authorization: valid_attributes.merge(crm_type: "invented") },
        headers: headers_for(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a field it does not accept rather than discarding it" do
      post api_v1_authorization_boundary_leveraged_authorizations_path(boundary),
        params: { leveraged_authorization: valid_attributes.merge(uuid: SecureRandom.uuid) },
        headers: headers_for(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join(" ")).to include("uuid")
    end
  end

  describe "GET .../leveraged_authorizations" do
    it "lists only this boundary's relationships" do
      mine = create(:leveraged_authorization, leveraging_boundary: boundary,
                                              leveraged_boundary: leveraged)
      other_boundary = create(:authorization_boundary, organization: organization)
      create(:leveraged_authorization, leveraging_boundary: other_boundary)

      get api_v1_authorization_boundary_leveraged_authorizations_path(boundary),
        headers: headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].map { |r| r["id"] }).to contain_exactly(mine.id)
    end

    it "refuses a non-member" do
      get api_v1_authorization_boundary_leveraged_authorizations_path(boundary),
        headers: headers_for(outsider)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST .../leveraged_authorizations/:id/populate" do
    it "reports how many inheritance links it imported" do
      record = create(:leveraged_authorization, leveraging_boundary: boundary,
                                                leveraged_boundary: leveraged)
      allow(LeveragedAuthorizationService).to receive(:populate_from_leveraged!).and_return(3)

      post populate_api_v1_authorization_boundary_leveraged_authorization_path(boundary, record),
        headers: headers_for(member), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "inheritance_links_populated")).to eq(3)
    end

    it "refuses a non-member, and does not run the import" do
      record = create(:leveraged_authorization, leveraging_boundary: boundary,
                                                leveraged_boundary: leveraged)
      expect(LeveragedAuthorizationService).not_to receive(:populate_from_leveraged!)

      post populate_api_v1_authorization_boundary_leveraged_authorization_path(boundary, record),
        headers: headers_for(outsider), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE .../leveraged_authorizations/:id" do
    it "removes the record" do
      record = create(:leveraged_authorization, leveraging_boundary: boundary,
                                                leveraged_boundary: leveraged)

      expect {
        delete api_v1_authorization_boundary_leveraged_authorization_path(boundary, record),
          headers: headers_for(member)
      }.to change { boundary.leveraging_relationships.count }.by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "deleted")).to be(true)
    end

    it "refuses a non-member, and the record survives" do
      record = create(:leveraged_authorization, leveraging_boundary: boundary,
                                                leveraged_boundary: leveraged)

      expect {
        delete api_v1_authorization_boundary_leveraged_authorization_path(boundary, record),
          headers: headers_for(outsider)
      }.not_to change { boundary.leveraging_relationships.count }

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for a record on another boundary" do
      other_boundary = create(:authorization_boundary, organization: organization)
      record = create(:leveraged_authorization, leveraging_boundary: other_boundary)

      delete api_v1_authorization_boundary_leveraged_authorization_path(boundary, record),
        headers: headers_for(admin)

      expect(response).to have_http_status(:not_found)
      expect(LeveragedAuthorization.exists?(record.id)).to be(true)
    end
  end
end
