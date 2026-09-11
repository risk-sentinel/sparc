# frozen_string_literal: true

require "rails_helper"

# #1044 — the admin gate must accept an IdP-granted, time-boxed administrator,
# and must still refuse everyone else.
#
# Exercised through a REQUEST, not by calling the predicate: the whole point of
# consolidating the five `authorize_admin!` definitions first was that four
# controllers shadowed the shared gate, and only a request proves which
# definition actually ran. `roles` is one of those four.
RSpec.describe "the admin gate honours IdP-granted authority (#1044)", type: :request do
  let(:instance_admin_role) do
    Role.find_or_create_by!(name: "instance_admin") do |role|
      role.display_name = "Instance Administrator"
      role.scope        = "instance"
      role.permissions  = { "admin.administer" => true }
    end
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "GET /api/v1/roles" do
    it "REFUSES an ordinary user" do
      user = create(:user, admin: false)
      token = ApiToken.generate!(user: user, name: "ordinary").plaintext_token

      get "/api/v1/roles", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:forbidden)
    end

    # The allow leg uses a NON-ADMIN holding the grant. An allow leg proved with
    # an admin proves only that admins work, which was never in question.
    it "ALLOWS a non-admin holding the IdP-granted instance role" do
      user = create(:user, admin: false)
      user.user_roles.create!(role: instance_admin_role, authorization_boundary: nil, source: "idp")
      token = ApiToken.generate!(user: user, name: "temp admin").plaintext_token

      get "/api/v1/roles", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:ok), "an IdP-granted instance admin was refused"
      expect(user.reload.admin?).to be(false), "the allow leg must not be an admin"
    end

    it "REFUSES again once the grant is revoked" do
      user = create(:user, admin: false)
      grant = user.user_roles.create!(role: instance_admin_role, authorization_boundary: nil, source: "idp")
      token = ApiToken.generate!(user: user, name: "temp admin").plaintext_token

      get "/api/v1/roles", headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)

      grant.destroy!

      get "/api/v1/roles", headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:forbidden),
                          "authority outlived the grant — a revoked administrator kept power"
    end
  end

  # The wording override introduced when the four shadowing copies were removed.
  it "still refuses with the controller's own message" do
    user = create(:user, admin: false)
    token = ApiToken.generate!(user: user, name: "ordinary").plaintext_token

    get "/api/v1/roles", headers: { "Authorization" => "Bearer #{token}" }

    expect(response.parsed_body["error"]).to eq("Forbidden")
  end
end
