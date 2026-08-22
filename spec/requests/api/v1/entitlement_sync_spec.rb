# frozen_string_literal: true

require "rails_helper"

# #860 — the dry run the epic asks for BEFORE authoritative is switched on.
#
# The question an operator has is not "is my config valid" but "if I turn this
# on, what happens to my people?" These examples are mostly about the preview
# answering that honestly — and, above all, about it writing nothing.
RSpec.describe "Api::V1 entitlement sync", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }
  let(:organization) { create(:organization, name: "Acme") }
  let(:boundary) { create(:authorization_boundary, name: "Acme Prod", organization: organization) }
  let!(:isso) { Role.find_by(name: "isso") || create(:role, name: "isso", scope: "authorization_boundary") }

  def token_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "GET /api/v1/entitlement_sync" do
    it "reports the mode and what the sync currently owns" do
      member.user_roles.create!(role: isso, authorization_boundary: boundary, source: "idp")

      get "/api/v1/entitlement_sync", headers: token_for(admin)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data["mode"]).to eq("off")
      expect(data["modes"]).to eq(%w[off bootstrap authoritative])
      expect(data.dig("managed", "user_roles")).to eq(1)
    end

    it "says whether the groups SCOPE was actually requested" do
      # The commonest support case: the claim is configured and the scope is
      # missing, so nothing arrives and the configuration looks correct.
      allow(SparcConfig).to receive(:oidc_scopes).and_return("openid profile email")

      get "/api/v1/entitlement_sync", headers: token_for(admin)

      expect(response.parsed_body.dig("data", "grants_scope_requested")).to be(false)

      allow(SparcConfig).to receive(:oidc_scopes).and_return("openid profile email groups")
      get "/api/v1/entitlement_sync", headers: token_for(admin)

      expect(response.parsed_body.dig("data", "grants_scope_requested")).to be(true)
    end

    it "refuses a non-admin" do
      get "/api/v1/entitlement_sync", headers: token_for(member)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/entitlement_sync/preview" do
    it "shows what would be added, and writes nothing" do
      boundary

      expect {
        post "/api/v1/entitlement_sync/preview",
             params: { preview: { user_id: member.id, mode: "bootstrap",
                                  grants: [ "sparc:boundary:acme:acme-prod:isso" ] } },
             headers: token_for(admin)
      }.not_to change(UserRole, :count)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data["dry_run"]).to be(true)
      expect(data["changes"].first).to include("action" => "add", "role" => "isso",
                                               "authorization_boundary" => "acme-prod")
    end

    it "previews what AUTHORITATIVE would revoke, while running in another mode" do
      # The whole point of the dry run: ask the dangerous question safely.
      member.user_roles.create!(role: isso, authorization_boundary: boundary, source: "idp")

      expect {
        post "/api/v1/entitlement_sync/preview",
             params: { preview: { user_id: member.id, mode: "authoritative", grants: [] } },
             headers: token_for(admin)
      }.not_to change(UserRole, :count)

      expect(response.parsed_body.dig("data", "changes").first["action"]).to eq("revoke")
    end

    it "distinguishes an ABSENT grants list from an empty one" do
      # Absent = the claim was not in the token, which syncs nothing. Empty =
      # the person has no grants. Previewing them the same way would hide the
      # misconfiguration this feature most often meets.
      member.user_roles.create!(role: isso, authorization_boundary: boundary, source: "idp")

      post "/api/v1/entitlement_sync/preview",
           params: { preview: { user_id: member.id, mode: "authoritative" } }, headers: token_for(admin)
      expect(response.parsed_body.dig("data", "error")).to match(/not present in the token/)

      post "/api/v1/entitlement_sync/preview",
           params: { preview: { user_id: member.id, mode: "authoritative", grants: [] } },
           headers: token_for(admin)
      expect(response.parsed_body.dig("data", "error")).to be_nil
      expect(response.parsed_body.dig("data", "changes").first["action"]).to eq("revoke")
    end

    it "reports grants it cannot resolve, with the reason" do
      post "/api/v1/entitlement_sync/preview",
           params: { preview: { user_id: member.id, mode: "bootstrap",
                                grants: [ "sparc:boundary:nope:nope-prod:isso" ] } },
           headers: token_for(admin)

      unmatched = response.parsed_body.dig("data", "unmatched").first
      expect(unmatched["grant"]).to eq("sparc:boundary:nope:nope-prod:isso")
      expect(unmatched["reason"]).to match(/not found/)
    end

    it "names an unknown mode and lists what it accepts" do
      post "/api/v1/entitlement_sync/preview",
           params: { preview: { user_id: member.id, mode: "aggressive" } }, headers: token_for(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["expected"]).to eq(%w[off bootstrap authoritative])
    end

    it "404s for an unknown user" do
      post "/api/v1/entitlement_sync/preview",
           params: { preview: { user_id: 999_999_999 } }, headers: token_for(admin)

      expect(response).to have_http_status(:not_found)
    end

    describe "authorization, both directions" do
      it "answers an admin" do
        post "/api/v1/entitlement_sync/preview",
             params: { preview: { user_id: member.id, grants: [] } }, headers: token_for(admin)

        expect(response).to have_http_status(:ok)
      end

      it "refuses a signed-in non-admin" do
        post "/api/v1/entitlement_sync/preview",
             params: { preview: { user_id: member.id, grants: [] } }, headers: token_for(member)

        expect(response).to have_http_status(:forbidden)
      end

      it "refuses an anonymous caller" do
        post "/api/v1/entitlement_sync/preview", params: { user_id: member.id }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

# #860 — the claim-presence check reads `permit`'s output, which is only safe
# because permit preserves a submitted empty array. If that ever stops being
# true, "the claim was empty" silently becomes "the claim was absent" and
# authoritative mode stops revoking. Pinned rather than assumed.
RSpec.describe "permit keeps a submitted empty array", type: :request do
  it "distinguishes an empty array from an omitted key" do
    submitted = ActionController::Parameters.new(preview: { user_id: 1, grants: [] })
                                            .require(:preview).permit(:user_id, grants: [])
    omitted = ActionController::Parameters.new(preview: { user_id: 1 })
                                          .require(:preview).permit(:user_id, grants: [])

    expect(submitted.key?(:grants)).to be(true),
      "permit dropped an empty array; an empty claim now reads as an absent one"
    expect(omitted.key?(:grants)).to be(false)
  end
end
