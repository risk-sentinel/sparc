# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::AuthoritativeSources", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }
  let(:peer) do
    FederationPeer.create!(name: "Peer1", base_url: "https://peer1.example.gov",
                           signing_secret: "k" * 32, service_token: "tok")
  end
  let(:authoritative_resource) do
    BackMatterResource.create!(uuid: SecureRandom.uuid, title: "Auth",
                               source: "authoritative", globally_available: true,
                               promotion_status: "approved")
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "GET /api/v1/authoritative_sources/export" do
    it "returns a signed envelope of authoritative resources for the named peer" do
      authoritative_resource

      get export_api_v1_authoritative_sources_path,
          params: { peer: peer.name }, headers: admin_headers

      expect(response).to have_http_status(:ok)
      envelope = JSON.parse(response.body)
      expect(envelope["alg"]).to eq("HS256")
      verification = FederationBundleSigningService.verify(envelope, peer: peer)
      expect(verification).to be_success
      titles = verification.payload["resources"].map { |r| r["title"] }
      expect(titles).to include("Auth")
    end

    it "rejects callers without back_matter.federate or admin" do
      bystander = create(:user)
      bystander_token = ApiToken.generate!(user: bystander, name: "x")
      get export_api_v1_authoritative_sources_path,
          params: { peer: peer.name },
          headers: { "Authorization" => "Bearer #{bystander_token.plaintext_token}" }
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 422 for an unknown peer name" do
      get export_api_v1_authoritative_sources_path,
          params: { peer: "no-such-peer" }, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v1/authoritative_sources/import" do
    it "imports a signed bundle from a known peer" do
      # Build a bundle locally on behalf of the peer, then submit it.
      authoritative_resource
      envelope = AuthoritativeSourceFederationService.build_export_bundle(peer: peer)
      original_uuid = JSON.parse(Base64.urlsafe_decode64(envelope["payload"]))
                          .dig("resources", 0, "uuid")
      BackMatterResource.find_by(uuid: original_uuid)&.destroy!

      post import_api_v1_authoritative_sources_path,
           params: envelope.merge(peer: peer.name),
           headers: admin_headers, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["imported"].size).to eq(1)
      expect(data["bundle_uuid"]).to be_present
      expect(BackMatterResource.find_by(original_uuid: original_uuid)).to be_present
    end

    it "rejects a bundle whose signature does not verify" do
      authoritative_resource
      envelope = AuthoritativeSourceFederationService
                   .build_export_bundle(peer: peer)
                   .merge("signature" => "0" * 64)

      post import_api_v1_authoritative_sources_path,
           params: envelope.merge(peer: peer.name),
           headers: admin_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/Signature verification failed/i)
    end
  end

  describe "POST /api/v1/authoritative_sources (#646 create)" do
    it "creates an org/boundary-scoped source by default and returns 201" do
      expect {
        post api_v1_authoritative_sources_path,
             params: { back_matter_resource: { title: "API Source", rel: "reference" } },
             headers: admin_headers, as: :json
      }.to change(BackMatterResource, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body.dig("data", "title")).to eq("API Source")

      r = BackMatterResource.order(:created_at).last
      expect(r.source).to eq("managed")
      expect(r.globally_available).to be(false)
    end

    it "self-promotes to instance-wide for an admin when instance_wide is set" do
      post api_v1_authoritative_sources_path,
           params: { back_matter_resource: { title: "API Global", rel: "reference" },
                     instance_wide: true },
           headers: admin_headers, as: :json

      expect(response).to have_http_status(:created)
      r = BackMatterResource.order(:created_at).last
      expect(r.globally_available).to be(true)
      expect(r.source).to eq("authoritative")
    end

    it "queues instance-wide for a non-privileged token holder" do
      bystander = create(:user)
      token = ApiToken.generate!(user: bystander, name: "x")

      post api_v1_authoritative_sources_path,
           params: { back_matter_resource: { title: "API Wants Global", rel: "reference" },
                     instance_wide: true },
           headers: { "Authorization" => "Bearer #{token.plaintext_token}" }, as: :json

      expect(response).to have_http_status(:created)
      r = BackMatterResource.order(:created_at).last
      expect(r.globally_available).to be(false)
      expect(r.promotion_status).to eq("pending_review")
    end

    it "rejects an unauthenticated request" do
      post api_v1_authoritative_sources_path,
           params: { back_matter_resource: { title: "Nope" } }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 422 on a validation error" do
      post api_v1_authoritative_sources_path,
           params: { back_matter_resource: { title: "" } },
           headers: admin_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
