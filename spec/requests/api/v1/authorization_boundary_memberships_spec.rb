# frozen_string_literal: true

require "rails_helper"

# #875 — the boundary personnel roster was the one mutation SPARC offered only
# through the UI. These specs cover the endpoint that closes that gap: the happy
# path for each verb, the auth/authorization boundary, and the role vocabulary,
# which the API must resolve exactly as the web controller does or the two
# surfaces disagree about what a role means.
RSpec.describe "Api::V1::AuthorizationBoundaryMemberships", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }
  let(:boundary) { create(:authorization_boundary) }

  # dotenv loads in test, so the committed .env can leak a configured role list
  # into these examples. Clear it; the configured-vocabulary examples set it
  # explicitly.
  around do |example|
    original = ENV["SPARC_AUTH_BOUNDARY_ROLES"]
    ENV.delete("SPARC_AUTH_BOUNDARY_ROLES")
    example.run
  ensure
    original.nil? ? ENV.delete("SPARC_AUTH_BOUNDARY_ROLES") : ENV["SPARC_AUTH_BOUNDARY_ROLES"] = original
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  def membership_path(membership)
    api_v1_authorization_boundary_membership_path(boundary.slug, membership)
  end

  def collection_path
    api_v1_authorization_boundary_memberships_path(boundary.slug)
  end

  describe "GET index" do
    it "lists the boundary's roster" do
      create(:authorization_boundary_membership, authorization_boundary: boundary, user_name: "Dana Reed")

      get collection_path, headers: auth_headers

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"].map { |m| m["user_name"] }).to include("Dana Reed")
      expect(parsed["meta"]).to include("page", "count")
    end

    it "is scoped to the boundary in the path" do
      other = create(:authorization_boundary)
      create(:authorization_boundary_membership, authorization_boundary: other, user_name: "Other Person")

      get collection_path, headers: auth_headers

      expect(JSON.parse(response.body)["data"].map { |m| m["user_name"] }).not_to include("Other Person")
    end

    it "filters by role, resolving the value the same way a write does" do
      create(:authorization_boundary_membership, authorization_boundary: boundary,
             user_name: "The ISSO", role: "isso")
      create(:authorization_boundary_membership, authorization_boundary: boundary,
             user_name: "The CISO", role: "ciso")

      get collection_path, params: { role: "ISSO" }, headers: auth_headers

      names = JSON.parse(response.body)["data"].map { |m| m["user_name"] }
      expect(names).to eq([ "The ISSO" ])
    end
  end

  describe "GET roles" do
    it "reports the built-in vocabulary with labels" do
      get roles_api_v1_authorization_boundary_memberships_path(boundary.slug), headers: auth_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["available"]).to include({ "value" => "isso", "label" => "ISSO" })
      expect(data["acceptable"]).to match_array(AuthorizationBoundaryMembership::DEFAULT_ROLES)
    end

    it "reports the CONFIGURED vocabulary, so a client need not hardcode the built-ins" do
      ENV["SPARC_AUTH_BOUNDARY_ROLES"] = "isso,security_champion:Security Champion"

      get roles_api_v1_authorization_boundary_memberships_path(boundary.slug), headers: auth_headers

      data = JSON.parse(response.body)["data"]
      expect(data["available"]).to eq([
        { "value" => "isso", "label" => "ISSO" },
        { "value" => "security_champion", "label" => "Security Champion" }
      ])
      # Narrowing the offered list must not narrow what existing records may hold.
      expect(data["acceptable"]).to include(*AuthorizationBoundaryMembership::DEFAULT_ROLES)
      expect(data["acceptable"]).to include("security_champion")
    end
  end

  describe "GET show" do
    it "returns the membership with its resolved role and label" do
      membership = create(:authorization_boundary_membership, authorization_boundary: boundary, role: "isso")

      get membership_path(membership), headers: auth_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["role"]).to eq("isso")
      expect(data["role_label"]).to eq("ISSO")
    end

    it "404s for a membership belonging to another boundary" do
      other = create(:authorization_boundary_membership, authorization_boundary: create(:authorization_boundary))

      get membership_path(other), headers: auth_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST create" do
    it "creates a member and audits it" do
      expect {
        post collection_path, headers: auth_headers, params: {
          authorization_boundary_membership: {
            user_name: "Dana Reed", user_email: "dana@example.gov", role: "isso"
          }
        }
      }.to change { boundary.authorization_boundary_memberships.count }.by(1)

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["user_name"]).to eq("Dana Reed")
      expect(data["role"]).to eq("isso")
      expect(AuditEvent.where(action: "api_authorization_boundary_membership_created")).to exist
    end

    # The API must not be a second, laxer door onto the role vocabulary.
    it "resolves a label or abbreviation to its built-in key, as the UI does" do
      post collection_path, headers: auth_headers, params: {
        authorization_boundary_membership: { user_name: "Dana Reed", role: "Authorizing Official (AO)" }
      }

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["data"]["role"]).to eq("authorizing_official")
    end

    it "accepts a configured custom role" do
      ENV["SPARC_AUTH_BOUNDARY_ROLES"] = "isso,Security Champion"

      post collection_path, headers: auth_headers, params: {
        authorization_boundary_membership: { user_name: "Dana Reed", role: "Security Champion" }
      }

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["data"]["role"]).to eq("security_champion")
    end

    it "refuses a role outside the configured vocabulary" do
      ENV["SPARC_AUTH_BOUNDARY_ROLES"] = "isso"

      expect {
        post collection_path, headers: auth_headers, params: {
          authorization_boundary_membership: { user_name: "Dana Reed", role: "Security Champion" }
        }
      }.not_to change { AuthorizationBoundaryMembership.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("is not an available role")
    end

    it "refuses a member with no name" do
      post collection_path, headers: auth_headers, params: {
        authorization_boundary_membership: { user_name: "", role: "isso" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH update" do
    it "updates the role and audits it" do
      membership = create(:authorization_boundary_membership, authorization_boundary: boundary, role: "isso")

      patch membership_path(membership), headers: auth_headers, params: {
        authorization_boundary_membership: { role: "ciso" }
      }

      expect(response).to have_http_status(:ok)
      expect(membership.reload.role).to eq("ciso")
      expect(AuditEvent.where(action: "api_authorization_boundary_membership_updated")).to exist
    end

    it "leaves a retired role editable, so config changes do not strand records" do
      ENV["SPARC_AUTH_BOUNDARY_ROLES"] = "Security Champion"
      membership = create(:authorization_boundary_membership, authorization_boundary: boundary,
                          role: "Security Champion")
      ENV["SPARC_AUTH_BOUNDARY_ROLES"] = "isso"

      patch membership_path(membership), headers: auth_headers, params: {
        authorization_boundary_membership: { user_name: "Renamed Person" }
      }

      expect(response).to have_http_status(:ok)
      expect(membership.reload.user_name).to eq("Renamed Person")
      expect(membership.role).to eq("security_champion")
    end
  end

  describe "DELETE destroy" do
    it "removes the member and audits it" do
      membership = create(:authorization_boundary_membership, authorization_boundary: boundary)

      expect {
        delete membership_path(membership), headers: auth_headers
      }.to change { boundary.authorization_boundary_memberships.count }.by(-1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["deleted"]).to be(true)
      expect(AuditEvent.where(action: "api_authorization_boundary_membership_deleted")).to exist
    end
  end

  describe "authentication and authorization" do
    it "refuses an unauthenticated request" do
      get collection_path

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a non-admin without boundary read access" do
      outsider = create(:user)
      token = ApiToken.generate!(user: outsider, name: "Outsider")

      get collection_path, headers: { "Authorization" => "Bearer #{token.plaintext_token}" }

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a WRITE from a reader who may only view the boundary" do
      reader = create(:user)
      token = ApiToken.generate!(user: reader, name: "Reader")
      allow_any_instance_of(User).to receive(:has_permission?) do |_u, key, **_opts|
        key == "authorization_boundaries.read"
      end

      post collection_path, headers: { "Authorization" => "Bearer #{token.plaintext_token}" }, params: {
        authorization_boundary_membership: { user_name: "Dana Reed", role: "isso" }
      }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
