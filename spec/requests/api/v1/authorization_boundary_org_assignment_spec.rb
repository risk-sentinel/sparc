# frozen_string_literal: true

require "rails_helper"

# #770 bug 6 — PATCH /api/v1/authorization_boundaries/:id/organization
RSpec.describe "Api::V1 boundary org assignment", type: :request do
  let(:org_a) { create(:organization) }
  let(:org_b) { create(:organization) }

  let(:admin)         { create(:user, :admin) }
  let(:admin_headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'a').plaintext_token}" } }

  let(:org_admin) do
    create(:user).tap { |u| create(:organization_membership, user: u, organization: org_a, role: "org_admin") }
  end
  let(:org_admin_headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: org_admin, name: 'oa').plaintext_token}" } }

  let(:outsider)         { create(:user) }
  let(:outsider_headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: outsider, name: 'o').plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def assign_path(boundary)
    organization_api_v1_authorization_boundary_path(boundary)
  end

  it "401s without a token" do
    b = create(:authorization_boundary, organization: nil)
    patch assign_path(b), params: { organization_id: org_a.id }
    expect(response).to have_http_status(:unauthorized)
  end

  context "instance admin" do
    it "assigns an unassigned boundary" do
      b = create(:authorization_boundary, organization: nil)
      patch assign_path(b), params: { organization_id: org_a.id }, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(b.reload.organization).to eq(org_a)
    end

    it "moves a boundary between organizations" do
      b = create(:authorization_boundary, organization: org_b)
      patch assign_path(b), params: { organization_id: org_a.id }, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(b.reload.organization).to eq(org_a)
    end

    it "clears the association with a null organization_id" do
      b = create(:authorization_boundary, organization: org_a)
      patch assign_path(b), params: { organization_id: nil }, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(b.reload.organization).to be_nil
    end
  end

  context "org_admin of the target org" do
    it "assigns an unassigned boundary into their org" do
      b = create(:authorization_boundary, organization: nil)
      patch assign_path(b), params: { organization_id: org_a.id }, headers: org_admin_headers
      expect(response).to have_http_status(:ok)
      expect(b.reload.organization).to eq(org_a)
    end

    it "403s trying to MOVE a boundary from another org, with an actionable message" do
      b = create(:authorization_boundary, organization: org_b)
      patch assign_path(b), params: { organization_id: org_a.id }, headers: org_admin_headers
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to match(/instance admin/i)
      expect(b.reload.organization).to eq(org_b)
    end
  end

  context "user without org_admin on the target org" do
    it "403s assigning even an unassigned boundary" do
      b = create(:authorization_boundary, organization: nil)
      patch assign_path(b), params: { organization_id: org_a.id }, headers: outsider_headers
      expect(response).to have_http_status(:forbidden)
      expect(b.reload.organization).to be_nil
    end
  end
end
