# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::RemediationTimelines", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  it "renders the SLA grid for an admin" do
    sign_in_as(create(:user, :admin))
    get "/admin/remediation_timelines"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Remediation Timelines")
    expect(response.body).to include("Critical")
  end

  it "upserts a cell and redirects" do
    sign_in_as(create(:user, :admin))
    patch "/admin/remediation_timelines", params: { baseline_level: "High", criticality: "Critical", days: 5 }
    expect(response).to redirect_to("/admin/remediation_timelines")
    expect(RemediationTimeline.find_by(baseline_level: "High", criticality: "Critical").days).to eq(5)
  end

  it "redirects a non-admin away" do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(create(:user))
    get "/admin/remediation_timelines"
    expect(response).to have_http_status(:found) # authorize_admin! redirects
  end
end
