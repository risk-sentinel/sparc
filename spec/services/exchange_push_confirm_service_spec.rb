# frozen_string_literal: true

require "rails_helper"

# #1354 — a push is confirmed only by a fresh pull from the registered
# address. ExchangePullService is stubbed for the pull's answer; the pushed
# bytes go through the real intake (validation and storage).
RSpec.describe ExchangePushConfirmService do
  let(:connection) { create(:exchange_connection) }
  let(:source) do
    create(:exchange_document_source, exchange_connection: connection,
                                      url: "https://trust.provider.example/package/vulnerability-detail-report.json")
  end
  let(:pushed) { Rails.root.join("samples/fedramp-package-demo/vulnerability-detail-report.json").binread }
  let(:receipt) do
    ExchangePushReceipt.create!(exchange_connection: connection, exchange_document_source: source,
                                sha256: Digest::SHA256.hexdigest(pushed), byte_size: pushed.bytesize,
                                signature_sha256: SecureRandom.hex(32), key_fingerprint: "a" * 16,
                                signed_at: Time.current, status: "pending")
                        .tap { |r| r.file.attach(io: StringIO.new(pushed), filename: "push") }
  end

  def pull_returns(status:, document: nil, error: nil)
    allow(ExchangePullService).to receive(:call).with(source)
                                                .and_return(ExchangePullService::Result.new(status: status, document: document, error: error))
  end

  it "confirms a push when the pulled bytes match, marks that version push-confirmed and drops the held bytes" do
    pulled = create(:received_document, authorization_boundary: connection.authorization_boundary,
                                        sha256: receipt.sha256, source: "pull")
    pull_returns(status: :stored, document: pulled)

    described_class.call(receipt)

    expect(receipt.reload).to have_attributes(status: "confirmed", received_document: pulled, reason: nil)
    expect(receipt.file).not_to be_attached
    expect(pulled.reload.push_confirmed).to be(true)
    expect(connection.reload.last_push_status).to eq("confirmed")
    expect(AuditEvent.find_by!(action: "exchange_push_confirmed").metadata).to include("received_document_id" => pulled.id)
  end

  it "confirms a push of a version already on record (the pull finds it unchanged)" do
    on_record = create(:received_document, authorization_boundary: connection.authorization_boundary,
                                           sha256: receipt.sha256, state: "accepted")
    pull_returns(status: :unchanged, document: on_record)

    expect(described_class.call(receipt).status).to eq("confirmed")
  end

  it "holds the pushed bytes as an unconfirmed push when the address returns something else" do
    other = create(:received_document, authorization_boundary: connection.authorization_boundary, source: "pull")
    pull_returns(status: :stored, document: other)

    described_class.call(receipt)

    expect(receipt.reload.status).to eq("unconfirmed")
    expect(receipt.reason).to include("differs from what was pushed")
    held = receipt.received_document
    expect(held).to have_attributes(source: "push", push_confirmed: false, sha256: receipt.sha256,
                                    stream_key: source.stream_key, state: "pending_review")
    expect(held.bytes).to eq(pushed)
    expect(receipt.file).not_to be_attached
    expect(AuditEvent.find_by!(action: "exchange_push_unconfirmed").metadata["reason"]).to include("differs")
  end

  it "holds the pushed bytes as an unconfirmed push when the address cannot be pulled" do
    pull_returns(status: :failed, error: "TLS key not pinned")

    described_class.call(receipt)

    expect(receipt.reload).to have_attributes(status: "unconfirmed")
    expect(receipt.reason).to include("could not be pulled: TLS key not pinned")
    expect(receipt.received_document).to have_attributes(push_confirmed: false, state: "pending_review")
    expect(connection.reload.last_push_status).to eq("unconfirmed")
  end

  it "never auto-accepts an unconfirmed push, even when a version is in effect for the stream" do
    in_effect = ReceivedDocumentService.call(boundary: connection.authorization_boundary, bytes: pushed.sub("2026-10", "2026-09"),
                                             source: "pull", document_source: source).document
    in_effect.update!(state: "accepted")
    pull_returns(status: :failed, error: "unreachable")

    described_class.call(receipt)

    expect(receipt.reload.received_document).to have_attributes(state: "pending_review", auto_accepted: false)
    expect(in_effect.reload.state).to eq("accepted")
  end

  it "records why when the pushed bytes cannot be received either" do
    receipt.file.attach(io: StringIO.new(" "), filename: "push")
    pull_returns(status: :failed, error: "unreachable")

    described_class.call(receipt)

    expect(receipt.reload.reason).to include("The pushed bytes were not stored: Empty document")
    expect(receipt.received_document).to be_nil
  end

  it "is unconfirmed when the document was removed from the connection, and pulls nothing" do
    receipt.update!(exchange_document_source: nil)
    allow(ExchangePullService).to receive(:call)

    expect(described_class.call(receipt).reason).to include("no longer registered")
    expect(ExchangePullService).not_to have_received(:call)
  end

  it "leaves a receipt that is already decided as it is" do
    receipt.update!(status: "confirmed")
    allow(ExchangePullService).to receive(:call)

    described_class.call(receipt)

    expect(ExchangePullService).not_to have_received(:call)
  end

  it "runs from ExchangePushConfirmJob, which ignores a receipt that no longer exists" do
    pull_returns(status: :failed, error: "unreachable")

    ExchangePushConfirmJob.perform_now(receipt.id)
    expect(receipt.reload.status).to eq("unconfirmed")
    expect { ExchangePushConfirmJob.perform_now(0) }.not_to raise_error
  end

  it "is confirmed by a later pull that finds the same bytes at the registered address" do
    pull_returns(status: :failed, error: "unreachable")
    described_class.call(receipt)
    held = receipt.reload.received_document
    expect(held.push_confirmed).to be(false)

    fetcher = instance_double(ExchangeFetcher)
    allow(ExchangeFetcher).to receive(:new).and_return(fetcher)
    allow(fetcher).to receive(:get).and_return(
      ExchangeFetcher::Result.new(body: pushed, content_type: "application/json", final_url: source.url, peer_ip: "203.0.113.10",
                                  spki_sha256: nil, status: 200, bytes: pushed.bytesize, sha256: receipt.sha256)
    )
    allow(ExchangePullService).to receive(:call).and_call_original

    expect(ExchangePullService.call(source).status).to eq(:unchanged)
    expect(held.reload.push_confirmed).to be(true)
    expect(AuditEvent.where(action: "exchange_push_confirmed").last.metadata).to include("by" => "pull")
  end
end
