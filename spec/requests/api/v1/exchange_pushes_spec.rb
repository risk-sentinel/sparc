# frozen_string_literal: true

require "rails_helper"

# #1354 — a provider's push over HTTP: no token, the signature is the
# credential. The body is the document; the confirming pull runs in a job.
RSpec.describe "API v1 exchange push", type: :request do
  include ActiveJob::TestHelper

  let(:key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:connection) { create(:exchange_connection, push_public_keys: [ Base64.strict_encode64(key.raw_public_key) ]) }
  let(:source) { create(:exchange_document_source, exchange_connection: connection) }
  let(:body) { Rails.root.join("samples/fedramp-package-demo/vulnerability-detail-report.json").binread }
  let(:path) { "/api/v1/exchange_connections/#{connection.id}/document_sources/#{source.id}/push" }

  # Sign-in on, so a token-free request is not admitted by the no-auth posture.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def signed_headers(timestamp: Time.current.to_i.to_s, payload: body, signing_key: key)
    { "CONTENT_TYPE" => "application/json", "SPARC-Push-Timestamp" => timestamp,
      "SPARC-Push-Signature" => push_signature(signing_key, connection_id: connection.id, document_source_id: source.id,
                                                            timestamp: timestamp, body: payload) }
  end

  it "202s a signed push with no token, and returns its pending receipt" do
    expect { post path, params: body, headers: signed_headers }.to have_enqueued_job(ExchangePushConfirmJob)

    expect(response).to have_http_status(:accepted)
    data = response.parsed_body["data"]
    expect(data).to include("status" => "pending", "exchange_document_source_id" => source.id,
                            "sha256" => Digest::SHA256.hexdigest(body), "byte_size" => body.bytesize)
  end

  it "confirms the push once the job pulls the same bytes from the registered address" do
    fetcher = instance_double(ExchangeFetcher)
    allow(ExchangeFetcher).to receive(:new).and_return(fetcher)
    allow(fetcher).to receive(:get).and_return(
      ExchangeFetcher::Result.new(body: body, content_type: "application/json", final_url: source.url, peer_ip: "203.0.113.10",
                                  spki_sha256: nil, status: 200, bytes: body.bytesize, sha256: Digest::SHA256.hexdigest(body))
    )

    perform_enqueued_jobs { post path, params: body, headers: signed_headers }

    receipt = ExchangePushReceipt.last
    expect(receipt.status).to eq("confirmed")
    expect(receipt.received_document).to have_attributes(source: "pull", push_confirmed: true, state: "pending_review")
    expect(fetcher).to have_received(:get).with(source.url)
  end

  it "401s an unsigned request, a token in place of a signature, and a signature by another key" do
    post path, params: body, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unauthorized)

    token = ApiToken.generate!(user: create(:user, :admin), name: "t").plaintext_token
    post path, params: body, headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:unauthorized)

    post path, params: body, headers: signed_headers(signing_key: OpenSSL::PKey.generate_key("ED25519"))
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "Push not accepted")
    expect(ExchangePushReceipt.count).to eq(0)
  end

  it "answers a connection that does not exist exactly as a bad signature, so it cannot be probed" do
    post "/api/v1/exchange_connections/0/document_sources/#{source.id}/push", params: body, headers: signed_headers
    unknown = [ response.status, response.body ]
    post path, params: body, headers: signed_headers(signing_key: OpenSSL::PKey.generate_key("ED25519"))

    expect([ response.status, response.body ]).to eq(unknown)
  end

  it "409s the same signed request sent twice" do
    headers = signed_headers
    post path, params: body, headers: headers
    post path, params: body, headers: headers

    expect(response).to have_http_status(:conflict)
    expect(ExchangePushReceipt.count).to eq(1)
  end

  it "413s a body over the upload limit before reading it, and audits it" do
    allow(SparcConfig).to receive(:max_upload_bytes).and_return(100)

    post path, params: body, headers: signed_headers

    expect(response).to have_http_status(:content_too_large)
    expect(AuditEvent.find_by!(action: "exchange_push_refused").metadata).to include("reason" => "too_large")
  end

  it "400s an empty push" do
    post path, params: "", headers: signed_headers(payload: "")
    expect(response).to have_http_status(:bad_request)
  end
end
