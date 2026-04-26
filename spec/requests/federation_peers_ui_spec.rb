# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Federation Peers UI", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    sign_in_as(admin)
    allow_any_instance_of(ApplicationController).to receive(:require_authentication).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:check_session_timeout).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:check_password_reset).and_return(true)
  end

  describe "GET /federation_peers" do
    it "lists peers" do
      FederationPeer.create!(name: "Alpha", base_url: "https://alpha.example.gov")
      get federation_peers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alpha")
    end

    it "redirects non-admin users" do
      sign_in_as(create(:user))
      get federation_peers_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /federation_peers" do
    it "creates a peer with secrets stored encrypted" do
      post federation_peers_path, params: {
        federation_peer: {
          name: "Beta", base_url: "https://beta.example.gov",
          enabled: "1", service_token: "secret-bearer", signing_secret: "hmac-key-xy"
        }
      }
      peer = FederationPeer.find_by(name: "Beta")
      expect(peer).to be_present
      expect(response).to redirect_to(federation_peer_path(peer))
      expect(peer.service_token).to eq("secret-bearer")
      expect(peer.signing_secret).to eq("hmac-key-xy")
      raw = ActiveRecord::Base.connection
                              .select_value("SELECT encrypted_signing_secret FROM federation_peers WHERE id = #{peer.id}")
      expect(raw).not_to include("hmac-key-xy")
    end

    it "renders the form with errors on invalid input" do
      post federation_peers_path, params: {
        federation_peer: { name: "", base_url: "ftp://nope" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("must be a valid http(s) URL")
    end
  end

  describe "PATCH /federation_peers/:id" do
    it "updates without overwriting an existing secret when blank" do
      peer = FederationPeer.create!(name: "Existing", base_url: "https://e.example.gov",
                                    signing_secret: "existing-key-padded-out-y")
      patch federation_peer_path(peer), params: {
        federation_peer: { name: "Existing", base_url: "https://e.example.gov", signing_secret: "" }
      }
      peer.reload
      expect(peer.signing_secret).to eq("existing-key-padded-out-y")
    end
  end

  describe "POST /federation_peers/:id/sync" do
    it "redirects to the show page with a success flash on a clean pull" do
      peer = FederationPeer.create!(name: "P", base_url: "https://p.example.gov",
                                    signing_secret: "k" * 32, service_token: "tok")
      result = AuthoritativeSourceFederationService::Result.new(
        success: true, imported: [], skipped: [], errors: [], bundle_uuid: SecureRandom.uuid
      )
      allow(AuthoritativeSourceFederationService).to receive(:pull).and_return(result)

      post sync_federation_peer_path(peer)
      expect(response).to redirect_to(federation_peer_path(peer))
      expect(flash[:success]).to match(/Pulled 0/)
    end
  end
end
