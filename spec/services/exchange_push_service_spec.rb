# frozen_string_literal: true

require "rails_helper"

# #1354 — a provider's signed push. Every check that admits a push, each
# proven in both directions: the signed request is accepted, and the same
# request with one thing wrong is refused, audited, and stores nothing.
#
# NIST SP 800-53: SC-23, AU-10, IA-9, AC-3, SC-5, AU-12.
RSpec.describe ExchangePushService do
  include ActiveJob::TestHelper

  let(:key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:connection) do
    create(:exchange_connection, push_public_keys: [ Base64.strict_encode64(key.raw_public_key) ])
  end
  let(:source) { create(:exchange_document_source, exchange_connection: connection) }
  let(:body) { Rails.root.join("samples/fedramp-package-demo/vulnerability-detail-report.json").binread }
  let(:timestamp) { Time.current.to_i.to_s }
  let(:remote_ip) { "198.51.100.7" }

  def push(body: self.body, timestamp: self.timestamp, signature: nil, connection_id: connection.id,
           source_id: source.id, signing_key: key, ip: remote_ip)
    signature ||= push_signature(signing_key, connection_id: connection_id, document_source_id: source_id,
                                              timestamp: timestamp, body: body)
    described_class.call(connection_id: connection_id, document_source_id: source_id, body: body,
                         timestamp: timestamp, signature: signature, remote_ip: ip, content_type: "application/json")
  end

  def refused_reason
    yield
    raise "expected the push to be refused"
  rescue ExchangePushService::Refused => e
    e
  end

  it "accepts a signed push: records a pending receipt with the pushed bytes and queues the confirming pull" do
    receipt = nil
    expect { receipt = push }.to have_enqueued_job(ExchangePushConfirmJob)

    expect(receipt).to have_attributes(status: "pending", exchange_document_source: source,
                                       sha256: Digest::SHA256.hexdigest(body), byte_size: body.bytesize,
                                       key_fingerprint: ExchangeConnection.key_fingerprint(connection.push_public_keys.first),
                                       remote_ip: remote_ip)
    expect(receipt.bytes).to eq(body)
    expect(connection.reload).to have_attributes(last_push_status: "pending")
    expect(AuditEvent.find_by!(action: "exchange_push_received").metadata).to include("push_receipt_id" => receipt.id)
    expect(ReceivedDocument.count).to eq(0)
  end

  it "accepts the provider's second key, so it can rotate" do
    next_key = OpenSSL::PKey.generate_key("ED25519")
    connection.update!(push_public_keys: connection.push_public_keys + [ Base64.strict_encode64(next_key.raw_public_key) ])

    expect(push(signing_key: next_key).key_fingerprint)
      .to eq(Digest::SHA256.hexdigest(next_key.raw_public_key).first(16))
  end

  describe "refusals" do
    it "refuses a signature by a key that is not pinned" do
      error = refused_reason { push(signing_key: OpenSSL::PKey.generate_key("ED25519")) }
      expect([ error.reason, error.status ]).to eq([ :bad_signature, :unauthorized ])
    end

    it "refuses a body other than the one signed" do
      signature = push_signature(key, connection_id: connection.id, document_source_id: source.id,
                                      timestamp: timestamp, body: body)
      error = refused_reason { push(body: body.sub("2026", "2025"), signature: signature) }
      expect(error.reason).to eq(:bad_signature)
    end

    it "refuses a signature made for another document of the connection" do
      other = create(:exchange_document_source, exchange_connection: connection)
      signature = push_signature(key, connection_id: connection.id, document_source_id: other.id,
                                      timestamp: timestamp, body: body)
      expect(refused_reason { push(signature: signature) }.reason).to eq(:bad_signature)
    end

    it "refuses a timestamp more than 5 minutes from SPARC's clock, either way, and one that is not a number" do
      expect(refused_reason { push(timestamp: 6.minutes.ago.to_i.to_s) }.reason).to eq(:stale)
      expect(refused_reason { push(timestamp: 6.minutes.from_now.to_i.to_s) }.reason).to eq(:stale)
      expect(push(timestamp: 4.minutes.ago.to_i.to_s)).to be_pending
      expect(refused_reason { push(timestamp: "2026-11-22T10:00:00Z") }.reason).to eq(:bad_timestamp)
    end

    it "refuses the same signed request a second time (replay)" do
      signature = push_signature(key, connection_id: connection.id, document_source_id: source.id,
                                      timestamp: timestamp, body: body)
      push(signature: signature)

      error = refused_reason { push(signature: signature) }
      expect([ error.reason, error.status ]).to eq([ :replayed, :conflict ])
      expect(ExchangePushReceipt.count).to eq(1)
    end

    it "refuses a malformed signature" do
      expect(refused_reason { push(signature: "not-base64!") }.reason).to eq(:bad_signature)
      expect(refused_reason { push(signature: Base64.strict_encode64("x" * 63)) }.reason).to eq(:bad_signature)
    end

    it "refuses a connection with no key, a disabled one, and one that does not exist" do
      bare = create(:exchange_connection)
      bare_source = create(:exchange_document_source, exchange_connection: bare)
      expect(refused_reason { push(connection_id: bare.id, source_id: bare_source.id) }.reason).to eq(:push_not_enabled)

      connection.update!(enabled: false)
      expect(refused_reason { push }.reason).to eq(:push_not_enabled)

      expect(refused_reason { push(connection_id: 0) }.reason).to eq(:unknown_connection)
      expect(refused_reason { push(connection_id: "1 OR 1=1") }.reason).to eq(:unknown_connection)
    end

    it "refuses a document of another connection, and a disabled document" do
      foreign = create(:exchange_document_source)
      expect(refused_reason { push(source_id: foreign.id) }.reason).to eq(:unknown_document)

      source.update!(enabled: false)
      expect(refused_reason { push }.reason).to eq(:unknown_document)
    end

    it "refuses a caller outside the connection's IP ranges, and admits one inside" do
      connection.update!(allowed_cidrs: [ "203.0.113.0/24" ])

      expect(refused_reason { push(ip: "198.51.100.7") }.reason).to eq(:address_not_allowed)
      expect(refused_reason { push(ip: "") }.reason).to eq(:address_not_allowed)
      expect(push(ip: "203.0.113.9")).to be_pending
    end

    it "refuses an empty body and one over the upload limit" do
      expect(refused_reason { push(body: "  ") }.status).to eq(:bad_request)

      allow(SparcConfig).to receive(:max_upload_bytes).and_return(10)
      error = refused_reason { push }
      expect([ error.reason, error.status ]).to eq([ :too_large, :content_too_large ])
    end

    it "audits each refusal with its reason, and tells the caller only that it was not accepted" do
      error = refused_reason { push(signing_key: OpenSSL::PKey.generate_key("ED25519")) }

      expect(error.message).to eq("Push not accepted")
      event = AuditEvent.find_by!(action: "exchange_push_refused")
      expect(event.metadata).to include("reason" => "bad_signature", "remote_ip" => remote_ip)
      expect(ExchangePushReceipt.count).to eq(0)
      expect(enqueued_jobs).to be_empty
    end
  end

  it "publishes the exact text a provider signs" do
    expect(described_class.signed_message(connection_id: 7, document_source_id: 9, timestamp: "1700000000", body: "abc"))
      .to eq("SPARC-PUSH-1\n7\n9\n1700000000\n#{Digest::SHA256.hexdigest('abc')}")
  end
end
