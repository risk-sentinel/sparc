# frozen_string_literal: true

require "rails_helper"

# #770 bug 6 — admin/organizations boundary association UI.
RSpec.describe "Admin::Organizations boundary assignment", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:org)   { create(:organization) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    sign_in_as(admin)
  end

  it "renders the associate-boundary form on the org page" do
    create(:authorization_boundary, organization: nil, name: "Unassigned One")
    get admin_organization_path(org)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Associate a boundary")
    expect(response.body).to include("Unassigned One")
  end

  it "associates an unassigned boundary with the organization" do
    boundary = create(:authorization_boundary, organization: nil)
    post assign_boundary_admin_organization_path(org), params: { authorization_boundary_id: boundary.id }

    expect(response).to redirect_to(admin_organization_path(org))
    expect(boundary.reload.organization).to eq(org)
    follow_redirect!
    expect(response.body).to include("associated with #{org.name}")
  end

  it "moves a boundary from another org and reports the move (instance admin)" do
    other = create(:organization, name: "Prior Org")
    boundary = create(:authorization_boundary, organization: other)

    post assign_boundary_admin_organization_path(org), params: { authorization_boundary_id: boundary.id }

    expect(boundary.reload.organization).to eq(org)
    follow_redirect!
    expect(response.body).to include("moved from Prior Org")
  end

  it "excludes boundaries already in this org from the assignable list" do
    already = create(:authorization_boundary, organization: org, name: "Already Here")
    get admin_organization_path(org)
    # It appears in the linked table, but not as an assignable option row.
    expect(response.body).not_to include("#{already.name} — currently in")
  end
end
