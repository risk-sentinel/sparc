require "rails_helper"

RSpec.describe "LeveragedAuthorizations", type: :request do
  let(:org) { create(:organization) }
  let(:user) { create(:user, role: :admin) }
  let(:boundary_a) { create(:authorization_boundary, organization: org, name: "Alpha") }
  let(:boundary_b) { create(:authorization_boundary, organization: org, name: "Beta") }

  before { sign_in_as(user) }

  describe "POST /authorization_boundaries/:id/leveraged_authorizations" do
    it "creates a scenario-1 LA pointing at another same-org boundary" do
      expect do
        post authorization_boundary_leveraged_authorizations_path(boundary_a), params: {
          leveraged_authorization: {
            name: "Example IaaS",
            crm_type: "oscal_with_access",
            leveraged_boundary_id: boundary_b.id,
            date_authorized: "2026-01-15",
            description: "Test"
          }
        }
      end.to change { LeveragedAuthorization.count }.by(1)

      la = LeveragedAuthorization.last
      expect(la.leveraging_boundary_id).to eq(boundary_a.id)
      expect(la.leveraged_boundary_id).to eq(boundary_b.id)
      expect(response).to redirect_to(authorization_boundary_path(boundary_a))
    end
  end

  describe "DELETE /authorization_boundaries/:id/leveraged_authorizations/:id" do
    let!(:la) do
      create(:leveraged_authorization,
             leveraging_boundary: boundary_a, leveraged_boundary: boundary_b)
    end

    it "removes the LA" do
      expect do
        delete authorization_boundary_leveraged_authorization_path(boundary_a, la)
      end.to change { LeveragedAuthorization.count }.by(-1)
    end
  end
end
