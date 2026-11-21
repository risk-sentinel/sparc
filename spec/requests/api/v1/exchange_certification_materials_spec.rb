# frozen_string_literal: true

require "rails_helper"

# #1354 — a connection's Class A materials through the API, its push keys,
# Class A fields and push receipts on the connection endpoints.
RSpec.describe "API v1 Class A materials and push settings", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:admin) { create(:user, :admin) }
  let(:connection) { create(:exchange_connection, authorization_boundary: boundary, certification_class: "A") }
  let(:key) { OpenSSL::PKey.generate_key("ED25519") }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  def manager
    create(:user).tap do |u|
      create(:user_role, user: u, role: create(:role, permissions: { "connections.manage" => true }))
    end
  end

  def pdf_upload(text = "%PDF-1.7 report")
    Rack::Test::UploadedFile.new(StringIO.new(text), "application/pdf", original_filename: "soc2.pdf")
  end

  describe "materials" do
    it "adds a material (201), finds the same file again (200), and lists them" do
      post "/api/v1/exchange_connections/#{connection.id}/certification_materials",
           params: { kind: "soc2_report", file: pdf_upload }, headers: headers_for(manager)
      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data).to include("kind" => "soc2_report", "kind_label" => "SOC 2 Type II complete report",
                              "state" => "pending_review", "filename" => "soc2.pdf")
      expect(data.dig("links", "received_document")).to eq("/api/v1/authorization_boundaries/#{boundary.id}/received_documents/#{data['id']}")

      post "/api/v1/exchange_connections/#{connection.id}/certification_materials",
           params: { kind: "soc2_report", file: pdf_upload }, headers: headers_for(admin)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("unchanged")

      get "/api/v1/exchange_connections/#{connection.id}/certification_materials", headers: headers_for(admin)
      expect(response.parsed_body["data"].pluck("id")).to eq([ data["id"] ])
    end

    it "422s an unknown kind, a missing file, and a connection that is not Class A" do
      url = "/api/v1/exchange_connections/#{connection.id}/certification_materials"
      post url, params: { kind: "iso", file: pdf_upload }, headers: headers_for(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join).to include("soc2_report")

      post url, params: { kind: "soc2_report" }, headers: headers_for(admin)
      expect(response).to have_http_status(:unprocessable_content)

      connection.update!(certification_class: "B")
      post url, params: { kind: "soc2_report", file: pdf_upload }, headers: headers_for(admin)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "401s without a token and 403s without connections.manage across the instance" do
      url = "/api/v1/exchange_connections/#{connection.id}/certification_materials"
      get url
      expect(response).to have_http_status(:unauthorized)

      scoped = create(:user)
      create(:user_role, user: scoped, authorization_boundary_id: boundary.id,
                         role: create(:role, :authorization_boundary_scoped, permissions: { "connections.manage" => true }))
      [ create(:user), scoped ].each do |user|
        post url, params: { kind: "soc2_report", file: pdf_upload }, headers: headers_for(user)
        expect(response).to have_http_status(:forbidden)
      end
      expect(ReceivedDocument.count).to eq(0)
    end

    it "is decided on the boundary, and downloads as the file it was" do
      post "/api/v1/exchange_connections/#{connection.id}/certification_materials",
           params: { kind: "bridge_letter", file: pdf_upload("%PDF letter") }, headers: headers_for(manager)
      id = response.parsed_body.dig("data", "id")

      post "/api/v1/authorization_boundaries/#{boundary.id}/received_documents/#{id}/accept", headers: headers_for(admin)
      expect(response).to have_http_status(:ok)
      get "/api/v1/authorization_boundaries/#{boundary.id}/received_documents/#{id}/file", headers: headers_for(admin)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to eq("%PDF letter")
    end
  end

  describe "push keys, Class A and push receipts on the connection" do
    it "sets both through PATCH and returns them, with the 12-month expiry" do
      patch "/api/v1/exchange_connections/#{connection.id}", headers: headers_for(admin), as: :json,
            params: { exchange_connection: { push_public_keys: [ key.public_to_pem ], class_a_framework: "soc2_type2",
                                             class_a_certified_on: "2026-06-30" } }

      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data["push_public_keys"]).to eq([ Base64.strict_encode64(key.raw_public_key) ])
      expect(data["push_key_fingerprints"]).to eq([ Digest::SHA256.hexdigest(key.raw_public_key).first(16) ])
      expect(data["push_enabled"]).to be(true)
      expect(data["class_a"]).to include("framework" => "soc2_type2", "framework_label" => "SOC 2 Type II",
                                         "certified_on" => "2026-06-30", "expires_on" => "2027-06-30", "expired" => false)
    end

    it "422s a key that is not Ed25519, and refuses to set the expiry directly" do
      patch "/api/v1/exchange_connections/#{connection.id}", headers: headers_for(admin), as: :json,
            params: { exchange_connection: { push_public_keys: [ "bm90IGEga2V5" ] } }
      expect(response).to have_http_status(:unprocessable_content)

      patch "/api/v1/exchange_connections/#{connection.id}", headers: headers_for(admin), as: :json,
            params: { exchange_connection: { class_a_expires_on: "2099-01-01" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(connection.reload.class_a_expires_on).to be_nil
    end

    it "lists the connection's push receipts, newest first" do
      older = ExchangePushReceipt.create!(exchange_connection: connection, sha256: "a" * 64, signature_sha256: "1" * 64,
                                          key_fingerprint: "f" * 16, signed_at: 2.minutes.ago, status: "confirmed",
                                          created_at: 2.minutes.ago)
      newer = ExchangePushReceipt.create!(exchange_connection: connection, sha256: "b" * 64, signature_sha256: "2" * 64,
                                          key_fingerprint: "f" * 16, signed_at: 1.minute.ago, status: "unconfirmed",
                                          reason: "differs")

      get "/api/v1/exchange_connections/#{connection.id}/push_receipts", headers: headers_for(admin)

      expect(response.parsed_body["data"].pluck("id")).to eq([ newer.id, older.id ])
      expect(response.parsed_body["data"].first).to include("status" => "unconfirmed", "reason" => "differs")
    end
  end
end
