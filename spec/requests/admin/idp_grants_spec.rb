# frozen_string_literal: true

require "rails_helper"

# #860 — the unmatched-grant queue on screen. A thin client over the same
# UnmatchedGrantQuery the API and the digest email read.
RSpec.describe "Admin IdP grants", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def skip_grant(user: member, grant: "sparc:boundary:acme:not-yet:isso",
                 reason: 'authorization boundary "not-yet" not found')
    AuditEvent.log(user: user, action: "idp_grant_skipped", provider: "oidc",
                   metadata: { grant: grant, reason: reason })
  end

  describe "GET /admin/idp_grants" do
    it "shows a refused grant with its reason" do
      skip_grant
      sign_in_as(admin)

      get admin_idp_grants_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("not-yet")
      expect(response.body).to include("authorization boundary")
    end

    it "says so plainly when there is nothing outstanding" do
      sign_in_as(admin)

      get admin_idp_grants_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No grants were refused")
    end

    it "explains that nothing needs clearing" do
      # The screen has to say this or an administrator will look for a button to
      # dismiss rows that resolve on their own.
      skip_grant
      sign_in_as(admin)

      get admin_idp_grants_path

      expect(response.body).to match(/resolves by itself/i)
    end

    it "honours the window parameter" do
      sign_in_as(admin)

      get admin_idp_grants_path, params: { days: 7 }

      expect(response).to have_http_status(:ok)
    end

    describe "authorization, both directions" do
      it "refuses a signed-in non-admin" do
        sign_in_as(member)

        get admin_idp_grants_path

        expect(response).not_to have_http_status(:ok)
      end

      it "refuses an anonymous visitor" do
        get admin_idp_grants_path

        expect(response).not_to have_http_status(:ok)
      end
    end
  end
end
