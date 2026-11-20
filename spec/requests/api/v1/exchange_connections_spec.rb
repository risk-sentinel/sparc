# frozen_string_literal: true

require "rails_helper"

# #1354 — connections to other systems and the documents each pulls. Instance
# authority (connections.manage), a write-only credential, and Discover / Test
# that fetch and store nothing. ExchangeFetcher is stubbed: no network.
RSpec.describe "API v1 exchange connections", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:admin) { create(:user, :admin) }
  let(:secret) { "s3cr3t-bearer-value-never-echoed" }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  def user_with(permissions, boundary_id: nil)
    user = create(:user)
    role = if boundary_id
      create(:role, :authorization_boundary_scoped, permissions: permissions)
    else
      create(:role, permissions: permissions)
    end
    create(:user_role, user: user, role: role, authorization_boundary_id: boundary_id)
    user
  end

  let(:admin_headers) { headers_for(admin) }
  let(:manager_headers) { headers_for(user_with({ "connections.manage" => true })) }

  let(:connection) do
    ExchangeConnection.create!(name: "Provider A", authorization_boundary: boundary, root_url: "https://trust.provider.example/",
                               auth_scheme: "bearer", credential: secret, fedramp_id: "FR2400000001")
  end
  let!(:source) do
    connection.document_sources.create!(url: "https://trust.provider.example/package/vdr.json", format: "fedramp",
                                        document_type: "vulnerability-detail-report")
  end

  let(:vdr) do
    { "certificationPackageOverviewUri" => "https://trust.provider.example/package/cpo.json",
      "reportPeriod" => { "from" => "2026-10-01T00:00:00Z", "to" => "2026-10-31T23:59:59Z" },
      "vulnerabilities" => [] }.to_json
  end

  def fetched(body, url: source.url)
    ExchangeFetcher::Result.new(body: body, content_type: "application/json", final_url: url, peer_ip: "203.0.113.10",
                                spki_sha256: nil, status: 200, bytes: body.bytesize, sha256: Digest::SHA256.hexdigest(body))
  end

  let(:fetcher) { instance_double(ExchangeFetcher) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(ExchangeFetcher).to receive(:new).and_return(fetcher)
  end

  def expect_no_secret
    expect(response.body).not_to include(secret)
    expect(response.body).not_to include("encrypted_credential")
  end

  describe "authorization" do
    it "401s without a token" do
      get "/api/v1/exchange_connections"
      expect(response).to have_http_status(:unauthorized)
    end

    it "403s a caller without connections.manage" do
      get "/api/v1/exchange_connections", headers: headers_for(create(:user))
      expect(response).to have_http_status(:forbidden)
    end

    it "403s connections.manage held only on a boundary: the authority is instance-wide" do
      scoped = user_with({ "connections.manage" => true }, boundary_id: boundary.id)
      get "/api/v1/exchange_connections", headers: headers_for(scoped)
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/exchange_connections/#{connection.id}/pull", headers: headers_for(scoped)
      expect(response).to have_http_status(:forbidden)
    end

    it "403s every mutating action for a bystander, and nothing changes" do
      bystander = headers_for(create(:user))
      post "/api/v1/exchange_connections", params: { exchange_connection: { name: "X" } }, headers: bystander, as: :json
      expect(response).to have_http_status(:forbidden)
      patch "/api/v1/exchange_connections/#{connection.id}", params: { exchange_connection: { name: "Y" } },
                                                              headers: bystander, as: :json
      expect(response).to have_http_status(:forbidden)
      delete "/api/v1/exchange_connections/#{connection.id}", headers: bystander
      expect(response).to have_http_status(:forbidden)
      post "/api/v1/exchange_connections/#{connection.id}/document_sources",
           params: { exchange_document_source: { url: "https://trust.provider.example/x.json", format: "oscal" } },
           headers: bystander, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(connection.reload.name).to eq("Provider A")
      expect(connection.document_sources.count).to eq(1)
    end

    it "admits connections.manage held across the instance" do
      get "/api/v1/exchange_connections", headers: manager_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].map { |c| c["id"] }).to eq([ connection.id ])
    end
  end

  describe "CRUD" do
    it "creates a connection with a write-only credential, pins as arrays, and audits it" do
      pin = "ab" * 32
      expect {
        post "/api/v1/exchange_connections", params: { exchange_connection: {
          name: "Provider B", authorization_boundary_id: boundary.slug, root_url: "https://b.example/",
          auth_scheme: "header", auth_header_name: "X-Api-Key", credential: secret,
          fedramp_id: "fr2400000002", certification_class: "B", certification_type: "20x",
          spki_sha256: [ pin ], allowed_cidrs: [ "203.0.113.0/24" ]
        } }, headers: manager_headers, as: :json
      }.to change { AuditEvent.where(action: "exchange_connection_created").count }.by(1)

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data).to include("name" => "Provider B", "authorization_boundary_id" => boundary.id,
                              "fedramp_id" => "FR2400000002", "credential_set" => true,
                              "spki_sha256" => [ pin ], "allowed_cidrs" => [ "203.0.113.0/24" ],
                              "pinned_hosts" => [ "b.example" ])
      expect(data).not_to have_key("credential")
      expect_no_secret
      expect(ExchangeConnection.find(data["id"]).credential).to eq(secret)
    end

    it "422s an invalid connection and names why" do
      post "/api/v1/exchange_connections", params: { exchange_connection: {
        name: "Bad", authorization_boundary_id: boundary.id, root_url: "http://plain.example/", spki_sha256: [ "nothex" ]
      } }, headers: manager_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join).to include("https://")
    end

    it "refuses a field it does not accept" do
      post "/api/v1/exchange_connections", params: { exchange_connection: {
        name: "C", authorization_boundary_id: boundary.id, encrypted_credential: "x"
      } }, headers: manager_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"]).to include("Unrecognized field: encrypted_credential")
    end

    it "shows a connection with its documents and never the credential" do
      get "/api/v1/exchange_connections/#{connection.id}", headers: admin_headers
      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data["credential_set"]).to be(true)
      expect(data["document_sources"].map { |s| s["url"] }).to eq([ source.url ])
      expect_no_secret
    end

    it "updates without touching the credential unless it is sent, and clears it when sent blank" do
      patch "/api/v1/exchange_connections/#{connection.id}", params: { exchange_connection: { enabled: false } },
                                                              headers: manager_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(connection.reload.enabled).to be(false)
      expect(connection.credential).to eq(secret)
      expect_no_secret

      patch "/api/v1/exchange_connections/#{connection.id}", params: { exchange_connection: { credential: "" } },
                                                              headers: manager_headers, as: :json
      expect(response.parsed_body.dig("data", "credential_set")).to be(false)
      event = AuditEvent.where(action: "exchange_connection_updated").last
      expect(event.metadata["credential_changed"]).to be(true)
      expect(event.metadata.to_json).not_to include(secret)
    end

    it "deletes a connection, keeps its received versions, and audits it" do
      doc = ReceivedDocumentService.call(boundary: boundary, bytes: vdr, source: "pull", document_source: source,
                                         format: "fedramp").document
      delete "/api/v1/exchange_connections/#{connection.id}", headers: manager_headers
      expect(response).to have_http_status(:ok)
      expect(ExchangeConnection.exists?(connection.id)).to be(false)
      expect(doc.reload.exchange_connection_id).to be_nil
      expect(AuditEvent.where(action: "exchange_connection_deleted").count).to eq(1)
    end
  end

  describe "document sources" do
    let(:path) { "/api/v1/exchange_connections/#{connection.id}/document_sources" }

    it "lists, adds, updates and removes a document, auditing each change" do
      get path, headers: manager_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].map { |s| s["id"] }).to eq([ source.id ])

      post path, params: { exchange_document_source: { url: "https://trust.provider.example/ssp.json", format: "oscal",
                                                       document_type: "ssp", pull_interval_hours: 12 } },
                 headers: manager_headers, as: :json
      expect(response).to have_http_status(:created)
      added = response.parsed_body["data"]
      expect(added).to include("format" => "oscal", "pull_interval_hours" => 12, "enabled" => true)

      patch "#{path}/#{added['id']}", params: { exchange_document_source: { enabled: false } },
                                      headers: manager_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "enabled")).to be(false)

      delete "#{path}/#{added['id']}", headers: manager_headers
      expect(response).to have_http_status(:ok)
      expect(connection.document_sources.count).to eq(1)
      expect(AuditEvent.where(action: %w[exchange_document_source_created exchange_document_source_updated
                                         exchange_document_source_deleted]).count).to eq(3)
    end

    it "422s a non-https address" do
      post path, params: { exchange_document_source: { url: "http://trust.provider.example/x.json", format: "oscal" } },
                 headers: manager_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s a document of another connection" do
      other = ExchangeConnection.create!(name: "Other", authorization_boundary: boundary)
      patch "/api/v1/exchange_connections/#{other.id}/document_sources/#{source.id}",
            params: { exchange_document_source: { enabled: false } }, headers: manager_headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(source.reload.enabled).to be(true)
    end
  end

  describe "POST .../pull" do
    it "pulls every enabled document now and returns each result" do
      allow(fetcher).to receive(:get).with(source.url).and_return(fetched(vdr))

      post "/api/v1/exchange_connections/#{connection.id}/pull", headers: manager_headers
      expect(response).to have_http_status(:ok)
      result = response.parsed_body.dig("data", "results").sole
      expect(result).to include("document_source_id" => source.id, "status" => "stored")
      expect(result.dig("received_document", "state")).to eq("pending_review")
      expect(boundary.received_documents.count).to eq(1)
      expect_no_secret
    end

    it "reports a failed fetch as that document's result" do
      allow(fetcher).to receive(:get).and_raise(ExchangeFetcher::Error.new(:status, "trust.provider.example answered HTTP 503.", status: 503))

      post "/api/v1/exchange_connections/#{connection.id}/pull", headers: manager_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "results", 0, "status")).to eq("failed")
      expect(source.reload.last_status).to eq("failed")
    end

    it "422s a disabled connection and fetches nothing" do
      connection.update!(enabled: false)
      expect(fetcher).not_to receive(:get)
      post "/api/v1/exchange_connections/#{connection.id}/pull", headers: manager_headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST .../discover" do
    it "lists the root's document links and stores nothing" do
      allow(fetcher).to receive(:discover).with(connection.root_url).and_return(
        [ { url: source.url, hint_format: "json" }, { url: "https://trust.provider.example/package/sdr.json", hint_format: "json" } ]
      )

      expect {
        post "/api/v1/exchange_connections/#{connection.id}/discover", headers: manager_headers
      }.not_to change { [ ExchangeDocumentSource.count, ReceivedDocument.count, connection.reload.updated_at ] }

      expect(response).to have_http_status(:ok)
      candidates = response.parsed_body.dig("data", "candidates")
      expect(candidates).to contain_exactly(
        { "url" => source.url, "hint_format" => "json", "registered" => true },
        { "url" => "https://trust.provider.example/package/sdr.json", "hint_format" => "json", "registered" => false }
      )
      expect(AuditEvent.where(action: "exchange_connection_discovered").count).to eq(1)
    end

    it "502s when the trust center cannot be reached" do
      allow(fetcher).to receive(:discover).and_raise(ExchangeFetcher::Error.new(:blocked_address, "resolves to a private address"))
      post "/api/v1/exchange_connections/#{connection.id}/discover", headers: manager_headers
      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body["reason"]).to eq("blocked_address")
    end

    it "422s a connection with no root address" do
      connection.update!(root_url: nil)
      post "/api/v1/exchange_connections/#{connection.id}/discover", headers: manager_headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST .../test_connection" do
    it "fetches and validates each document and stores nothing" do
      allow(fetcher).to receive(:get).with(connection.root_url).and_return(fetched("<html></html>", url: connection.root_url))
      allow(fetcher).to receive(:get).with(source.url).and_return(fetched(vdr))

      expect {
        post "/api/v1/exchange_connections/#{connection.id}/test_connection", headers: manager_headers
      }.not_to change { [ ReceivedDocument.count, source.reload.last_pulled_at, connection.reload.last_pulled_at ] }

      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data.dig("root", "reachable")).to be(true)
      tested = data["sources"].sole
      expect(tested).to include("document_source_id" => source.id, "reachable" => true, "status" => 200)
      expect(tested.dig("validation", "valid")).to be(true)
      expect(tested.dig("validation", "format")).to eq("fedramp")
      expect(AuditEvent.where(action: "exchange_connection_tested").count).to eq(1)
      expect_no_secret
    end

    it "reports an unreachable document without failing the request" do
      allow(fetcher).to receive(:get).with(connection.root_url).and_return(fetched("{}", url: connection.root_url))
      allow(fetcher).to receive(:get).with(source.url)
                                     .and_raise(ExchangeFetcher::Error.new(:pin_mismatch, "the server key matches no pin"))

      post "/api/v1/exchange_connections/#{connection.id}/test_connection", headers: manager_headers
      expect(response).to have_http_status(:ok)
      tested = response.parsed_body.dig("data", "sources").sole
      expect(tested).to include("reachable" => false, "reason" => "pin_mismatch")
      expect(tested["validation"]).to be_nil
    end

    it "422s a connection with no address at all, with the real fetcher (nothing to pin)" do
      allow(ExchangeFetcher).to receive(:new).and_call_original
      bare = ExchangeConnection.create!(name: "Bare", authorization_boundary: boundary)
      post "/api/v1/exchange_connections/#{bare.id}/test_connection", headers: manager_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["reason"]).to eq("configuration")
      post "/api/v1/exchange_connections/#{bare.id}/pull", headers: manager_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s a connection SPARC cannot fetch with" do
      allow(ExchangeFetcher).to receive(:new).and_raise(ArgumentError, "at least one allowed host is required")
      post "/api/v1/exchange_connections/#{connection.id}/test_connection", headers: manager_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["reason"]).to eq("configuration")
    end
  end
end
