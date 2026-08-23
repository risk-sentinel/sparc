# frozen_string_literal: true

require "rails_helper"

# #860 — the unmatched-grant queue.
#
# The answer to "what happens to a user whose claim names something that is not
# provisioned yet": the grant is refused, the user signs in with whatever else
# resolved, and the refusal lands HERE with its reason so an administrator can
# fix the estate rather than discovering it from a support ticket.
RSpec.describe "Api::V1 IdP grants", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }

  def token_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def skip_grant(user:, grant:, reason:, at: Time.current)
    travel_to(at) do
      AuditEvent.log(user: user, action: "idp_grant_skipped", provider: "oidc",
                     metadata: { grant: grant, reason: reason })
    end
  end

  describe "GET /api/v1/idp_grants/unmatched" do
    it "lists refused grants with the reason and who they affected" do
      skip_grant(user: member, grant: "sparc:boundary:acme:not-yet:isso",
                 reason: 'authorization boundary "not-yet" not found')

      get "/api/v1/idp_grants/unmatched", headers: token_for(admin)

      expect(response).to have_http_status(:ok)
      row = response.parsed_body["data"].first
      expect(row["grant"]).to eq("sparc:boundary:acme:not-yet:isso")
      expect(row["reason"]).to match(/not found/)
      expect(row["user"]["email"]).to eq(member.email)
    end

    it "counts DISTINCT users per reason, not raw occurrences" do
      # One person signing in five times is five events and ONE problem.
      # Reporting five would misrepresent how widespread it is.
      5.times { skip_grant(user: member, grant: "sparc:org:acme:member", reason: 'organization "acme" not found') }
      other = create(:user)
      skip_grant(user: other, grant: "sparc:org:acme:member", reason: 'organization "acme" not found')

      get "/api/v1/idp_grants/unmatched", headers: token_for(admin)

      summary = response.parsed_body.dig("meta", "summary").first
      expect(summary["occurrences"]).to eq(6)
      expect(summary["affected_users"]).to eq(2)
    end

    it "defaults to a 30 day window" do
      skip_grant(user: member, grant: "sparc:org:acme:member", reason: "old", at: 45.days.ago)
      skip_grant(user: member, grant: "sparc:org:acme:cio", reason: "recent", at: 2.days.ago)

      get "/api/v1/idp_grants/unmatched", headers: token_for(admin)

      grants = response.parsed_body["data"].map { |r| r["grant"] }
      expect(grants).to contain_exactly("sparc:org:acme:cio")
      expect(response.parsed_body.dig("meta", "window_days")).to eq(30)
    end

    it "widens the window on request, clamped to a year" do
      skip_grant(user: member, grant: "sparc:org:acme:member", reason: "old", at: 45.days.ago)

      get "/api/v1/idp_grants/unmatched", params: { days: 90 }, headers: token_for(admin)
      expect(response.parsed_body["data"].size).to eq(1)

      get "/api/v1/idp_grants/unmatched", params: { days: 9999 }, headers: token_for(admin)
      expect(response.parsed_body.dig("meta", "window_days")).to eq(365)
    end

    it "narrows to one user" do
      other = create(:user)
      skip_grant(user: member, grant: "sparc:org:acme:member", reason: "a")
      skip_grant(user: other, grant: "sparc:org:acme:cio", reason: "b")

      get "/api/v1/idp_grants/unmatched", params: { user_id: other.id }, headers: token_for(admin)

      expect(response.parsed_body["data"].map { |r| r["grant"] }).to eq([ "sparc:org:acme:cio" ])
    end

    it "does not report grants that were APPLIED" do
      AuditEvent.log(user: member, action: "idp_grant_applied", provider: "oidc",
                     metadata: { role: "isso" })

      get "/api/v1/idp_grants/unmatched", headers: token_for(admin)

      expect(response.parsed_body["data"]).to be_empty
    end

    describe "authorization, both directions" do
      it "answers an instance admin" do
        get "/api/v1/idp_grants/unmatched", headers: token_for(admin)

        expect(response).to have_http_status(:ok)
      end

      it "refuses a signed-in non-admin" do
        # The queue names organizations, boundaries and other users' emails —
        # the estate's shape, which is not general-reader information.
        get "/api/v1/idp_grants/unmatched", headers: token_for(member)

        expect(response).to have_http_status(:forbidden)
      end

      it "refuses an anonymous caller" do
        get "/api/v1/idp_grants/unmatched"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
