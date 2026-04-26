# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::FederationPeers", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "POST /api/v1/federation_peers" do
    it "creates a peer and accepts service_token + signing_secret as write-only fields" do
      post api_v1_federation_peers_path,
           params: { federation_peer: {
             name: "Peer A", base_url: "https://peer-a.example.gov",
             service_token: "secret-bearer", signing_secret: "long-shared-secret-32-bytes-x"
           } }, headers: admin_headers, as: :json

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["service_token_set"]).to eq(true)
      expect(data["signing_secret_set"]).to eq(true)
      expect(data).not_to have_key("service_token")
      expect(data).not_to have_key("signing_secret")

      peer = FederationPeer.find_by(name: "Peer A")
      expect(peer.service_token).to eq("secret-bearer")
      expect(peer.signing_secret).to eq("long-shared-secret-32-bytes-x")
    end

    it "returns 422 on invalid base_url" do
      post api_v1_federation_peers_path,
           params: { federation_peer: { name: "Bad", base_url: "ftp://nope" } },
           headers: admin_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "denies non-admin without back_matter.federate" do
      bystander = create(:user)
      bystander_token = ApiToken.generate!(user: bystander, name: "x")
      post api_v1_federation_peers_path,
           params: { federation_peer: { name: "X", base_url: "https://x.example.gov" } },
           headers: { "Authorization" => "Bearer #{bystander_token.plaintext_token}" },
           as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/federation_peers" do
    it "lists peers without leaking secrets" do
      FederationPeer.create!(name: "L", base_url: "https://l.example.gov",
                             service_token: "tk", signing_secret: "ss" * 16)

      get api_v1_federation_peers_path, headers: admin_headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data.first.keys).not_to include("service_token", "signing_secret",
                                             "encrypted_service_token", "encrypted_signing_secret")
    end
  end

  describe "PATCH /api/v1/federation_peers/:id" do
    it "rotates the signing_secret without changing the name" do
      peer = FederationPeer.create!(name: "Rotate", base_url: "https://r.example.gov",
                                    signing_secret: "old-secret-padded-out-x")
      patch api_v1_federation_peer_path(peer),
            params: { federation_peer: { signing_secret: "new-secret-padded-out-y" } },
            headers: admin_headers, as: :json

      expect(response).to have_http_status(:ok)
      peer.reload
      expect(peer.name).to eq("Rotate")
      expect(peer.signing_secret).to eq("new-secret-padded-out-y")
    end
  end

  describe "POST /api/v1/federation_peers/:id/sync" do
    let(:peer) do
      FederationPeer.create!(name: "Sync", base_url: "https://s.example.gov",
                             signing_secret: "k" * 32, service_token: "tok")
    end

    it "returns the import counts on a successful pull" do
      BackMatterResource.create!(uuid: SecureRandom.uuid, title: "Authoritative",
                                 source: "authoritative", globally_available: true,
                                 promotion_status: "approved")
      bundle  = AuthoritativeSourceFederationService.build_export_bundle(peer: peer)
      payload = FederationBundleSigningService.verify(bundle, peer: peer).payload
      BackMatterResource.find_by(uuid: payload["resources"].first["uuid"])&.destroy!

      stub = instance_double(Net::HTTPOK, body: bundle.to_json, code: "200", is_a?: false)
      allow(stub).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(AuthoritativeSourceFederationService).to receive(:http_get_export).and_return(stub)

      post sync_api_v1_federation_peer_path(peer), headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["imported"]).to eq(1)
    end

    it "returns 502-style status when the peer is unreachable" do
      stub = instance_double(Net::HTTPNotFound, code: "404", body: "", is_a?: false)
      allow(stub).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(AuthoritativeSourceFederationService).to receive(:http_get_export).and_return(stub)

      post sync_api_v1_federation_peer_path(peer), headers: admin_headers, as: :json
      expect(response).to have_http_status(:bad_gateway)
    end
  end
end
