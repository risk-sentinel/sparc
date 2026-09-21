# frozen_string_literal: true

require "rails_helper"

# #1155 — the federation identity constants, served so a peer reads or verifies
# them rather than embedding its own copy.
#
# The value these assertions protect is agreement. Object UUIDs are UUIDv5
# derived against one namespace UUID, and peers deduplicate WITHOUT coordinating
# only while every instance uses the same one. Two peers disagreeing does not
# error — the same logical object simply arrives under a second identity and
# nothing reconciles it (#1159). So the endpoint is asserted to publish exactly
# what the code derives, and the derivation is re-run here rather than restated.
RSpec.describe "Api::V1::FederationIdentities (#1155)", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  # A caller holding NO permissions at all. These constants identify the
  # federation rather than any tenant's data, so the allow leg has to be proven
  # with a non-admin — an admin passing proves only that break-glass works.
  let(:plain_user)     { create(:user) }
  let(:plain_token)    { ApiToken.generate!(user: plain_user, name: "Plain Test") }
  let(:plain_headers)  { { "Authorization" => "Bearer #{plain_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "authentication" do
    it "refuses an unauthenticated caller" do
      get "/api/v1/federation/identity"

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a bad token" do
      get "/api/v1/federation/identity", headers: { "Authorization" => "Bearer not-a-real-token" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/federation/identity" do
    it "serves the namespace URI and federation UUID to an authenticated caller" do
      get "/api/v1/federation/identity", headers: admin_headers

      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data["namespace_uri"]).to eq("https://sparc.risk-sentinel.org/ns")
      expect(data["federation_namespace_uuid"]).to eq("9f434272-f796-589b-b972-954790395630")
    end

    # The allow leg, with a permission-holding-nothing NON-admin: federation
    # constants are reference data and must not be gated behind a tenant scope.
    it "serves a caller with no permissions at all" do
      get "/api/v1/federation/identity", headers: plain_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "federation_namespace_uuid"))
        .to eq(OscalNamespace::FEDERATION_NAMESPACE)
    end

    it "publishes exactly what the code derives, not a second literal" do
      get "/api/v1/federation/identity", headers: admin_headers

      expect(response.parsed_body.dig("data", "federation_namespace_uuid"))
        .to eq(OscalNamespace.derived_federation_namespace)
    end

    it "describes the derivation so a peer can reproduce the UUID" do
      get "/api/v1/federation/identity", headers: admin_headers

      derivation = response.parsed_body.dig("data", "derivation")
      expect(derivation["method"]).to eq("uuidv5")
      expect(derivation["namespace"]).to eq("url")
      expect(derivation["name"]).to eq(response.parsed_body.dig("data", "namespace_uri"))

      # The published recipe must actually produce the published value.
      recomputed = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, derivation["name"])
      expect(recomputed).to eq(response.parsed_body.dig("data", "federation_namespace_uuid"))
    end

    # The deployment's own vocabulary is a DIFFERENT thing and varies per
    # install. Publishing them side by side is only safe if they stay distinct
    # in the response.
    it "reports the deployment's local namespace separately from the federation one" do
      allow(SparcConfig).to receive(:oscal_namespace).and_return("https://att.example/ns/oscal")

      get "/api/v1/federation/identity", headers: admin_headers

      expect(response.parsed_body.dig("meta", "instance_namespace")).to eq("https://att.example/ns/oscal")
      expect(response.parsed_body.dig("data", "namespace_uri")).to eq("https://sparc.risk-sentinel.org/ns")
    end

    # The two coincide by default — `SparcConfig.oscal_namespace` falls back to
    # SPARC's own entry — so a derivation wrongly built from the LOCAL namespace
    # looks correct until an operator sets one. Asserted under an override for
    # that reason: the published recipe must still compute the published UUID.
    it "does not vary the federation UUID or its derivation with the local namespace" do
      allow(SparcConfig).to receive(:oscal_namespace).and_return("https://att.example/ns/oscal")

      get "/api/v1/federation/identity", headers: admin_headers

      data = response.parsed_body["data"]
      expect(data["federation_namespace_uuid"]).to eq("9f434272-f796-589b-b972-954790395630")
      expect(data.dig("derivation", "name")).to eq("https://sparc.risk-sentinel.org/ns")

      recomputed = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, data.dig("derivation", "name"))
      expect(recomputed).to eq(data["federation_namespace_uuid"])
    end
  end

  # Deliberately absent from discovery, following the precedent /api/v1/guides
  # set: that registry advertises the scoped compliance-data surface, and
  # permission-free reference endpoints dilute the least-privilege view a
  # no-permission caller sees. Asserted rather than left implicit, so adding it
  # there later is a conscious decision and not an accident.
  describe "API discovery" do
    it "does not dilute the least-privilege view with this endpoint" do
      get "/api/v1/available", headers: plain_headers

      paths = response.parsed_body["endpoints"].map { |e| e["path"] }
      expect(paths).not_to include("/api/v1/federation/identity")
    end

    it "still serves the endpoint itself to that same caller" do
      get "/api/v1/federation/identity", headers: plain_headers

      expect(response).to have_http_status(:ok)
    end
  end
end
