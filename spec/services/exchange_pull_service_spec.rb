# frozen_string_literal: true

require "rails_helper"

# #1354 — pulling one registered document from its connection. ExchangeFetcher
# is stubbed (no network): its own rules are in exchange_fetcher_spec.rb. This
# covers what the pull does with the answer, and that the connection's own
# pins are what the fetcher is built with.
RSpec.describe ExchangePullService do
  let(:boundary) { create(:authorization_boundary) }
  let(:secret) { "pull-credential-value" }
  let(:pin) { "c" * 64 }
  let(:connection) do
    create(:exchange_connection, authorization_boundary: boundary, root_url: "https://trust.provider.example/",
                                 auth_scheme: "bearer", credential: secret, fedramp_id: "FR2400000001",
                                 spki_sha256: [ pin ], allowed_cidrs: [ "203.0.113.0/24" ])
  end
  let(:source) do
    create(:exchange_document_source, exchange_connection: connection,
                                      url: "https://cdn.provider.example/package/vdr.json")
  end
  let(:fetcher) { instance_double(ExchangeFetcher) }

  def vdr(to: "2026-10-31T23:59:59Z")
    { "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
      "reportPeriod" => { "from" => "2026-10-01T00:00:00Z", "to" => to }, "vulnerabilities" => [] }.to_json
  end

  def fetched(body)
    ExchangeFetcher::Result.new(body: body, content_type: "application/json", final_url: source.url,
                                peer_ip: "203.0.113.10", spki_sha256: pin, status: 200, bytes: body.bytesize,
                                sha256: Digest::SHA256.hexdigest(body))
  end

  def pull(user: nil) = described_class.call(source, user: user)

  before { allow(ExchangeFetcher).to receive(:new).and_return(fetcher) }

  it "builds the fetcher from the connection's pinned hosts, key pins, IP ranges and credential headers" do
    allow(fetcher).to receive(:get).and_return(fetched(vdr))

    pull

    expect(ExchangeFetcher).to have_received(:new).with(
      allowed_hosts: contain_exactly("trust.provider.example", "cdn.provider.example"),
      spki_sha256: [ pin ], allowed_cidrs: [ "203.0.113.0/24" ],
      headers: { "Authorization" => "Bearer #{secret}" }, max_bytes: SparcConfig.max_upload_bytes
    )
    expect(fetcher).to have_received(:get).with(source.url)
  end

  describe "a new version" do
    before { allow(fetcher).to receive(:get).and_return(fetched(vdr)) }

    it "is stored for review in the document's stream, with the source's format and type" do
      result = pull

      expect(result).to be_ok
      expect(result.status).to eq(:stored)
      expect(result.document).to have_attributes(source: "pull", state: "pending_review", stream_key: source.stream_key,
                                                 exchange_document_source_id: source.id,
                                                 exchange_connection_id: connection.id, fedramp_id: "FR2400000001",
                                                 filename: "vdr.json", content_type: "application/json",
                                                 received_by_id: nil, authorization_boundary_id: boundary.id)
    end

    it "records the pull on the source and the connection" do
      result = pull

      source.reload
      expect(source).to have_attributes(last_status: "stored", last_error: nil, last_sha256: result.document.sha256)
      expect(source.last_pulled_at).to be_within(5.seconds).of(Time.current)
      connection.reload
      expect(connection).to have_attributes(last_pull_status: "stored", last_error: nil)
      expect(connection.last_pulled_at).to be_within(5.seconds).of(Time.current)
    end

    it "audits the completed pull against the connection, with who asked" do
      user = create(:user)
      result = pull(user: user)

      event = AuditEvent.find_by!(action: "exchange_pull_completed")
      expect(event).to have_attributes(user_id: user.id, subject_type: "ExchangeConnection", subject_id: connection.id)
      expect(event.metadata).to include("document_source_id" => source.id, "url" => source.url, "status" => "stored",
                                        "received_document_id" => result.document.id, "sha256" => result.document.sha256)
      expect(event.metadata.to_json).not_to include(secret)
    end
  end

  it "records a byte-identical re-delivery as unchanged and stores nothing" do
    allow(fetcher).to receive(:get).and_return(fetched(vdr))
    first = pull.document

    result = nil
    expect { result = pull }.not_to change(ReceivedDocument, :count)

    expect(result).to be_ok
    expect(result.status).to eq(:unchanged)
    expect(result.document).to eq(first)
    expect(source.reload).to have_attributes(last_status: "unchanged", last_sha256: first.sha256)
    expect(connection.reload.last_pull_status).to eq("unchanged")
  end

  it "stores a fetched document that fails validation as invalid (owner, 2026-11-20)" do
    allow(fetcher).to receive(:get).and_return(fetched("not json at all"))

    result = pull

    expect(result.status).to eq(:stored)
    expect(result.document).to have_attributes(state: "invalid", format: "fedramp")
  end

  describe "a fetch that fails" do
    ExchangeFetcher::Error::REASONS.each do |reason|
      it "records #{reason} on the source and the connection, audits it, and stores nothing" do
        source.update_columns(last_sha256: "d" * 64)
        allow(fetcher).to receive(:get).and_raise(ExchangeFetcher::Error.new(reason, "Fetch failed: #{reason}"))

        result = nil
        expect { result = pull }.not_to change(ReceivedDocument, :count)

        expect(result).not_to be_ok
        expect(result).to have_attributes(status: :failed, error: "Fetch failed: #{reason}", document: nil)
        expect(source.reload).to have_attributes(last_status: "failed", last_error: "Fetch failed: #{reason}",
                                                 last_sha256: "d" * 64)
        expect(connection.reload).to have_attributes(last_pull_status: "failed", last_error: "Fetch failed: #{reason}")
        event = AuditEvent.find_by!(action: "exchange_pull_failed")
        expect(event.metadata).to include("status" => "failed", "error" => "Fetch failed: #{reason}")
      end
    end

    it "records a document SPARC refuses to receive (empty) as failed" do
      allow(fetcher).to receive(:get).and_return(fetched(""))
      result = pull
      expect(result).to have_attributes(status: :failed, error: "Empty document")
      expect(source.reload.last_status).to eq("failed")
    end

    it "keeps only the first 300 characters of the error in the audit record" do
      allow(fetcher).to receive(:get).and_raise(ExchangeFetcher::Error.new(:status, "x" * 1000))
      pull
      expect(AuditEvent.find_by!(action: "exchange_pull_failed").metadata["error"].size).to eq(300)
      expect(source.reload.last_error.size).to eq(1000)
    end
  end

  it "fetches nothing from a disabled connection, and records why" do
    connection.update!(enabled: false)
    allow(fetcher).to receive(:get)

    result = pull

    expect(result).to have_attributes(status: :failed, error: "The connection is disabled")
    expect(ExchangeFetcher).not_to have_received(:new)
    expect(source.reload).to have_attributes(last_status: "failed", last_error: "The connection is disabled")
    expect(AuditEvent.where(action: "exchange_pull_failed").count).to eq(1)
  end

  it "records settings the fetcher cannot enforce as 'not set up to pull', not a crash" do
    allow(ExchangeFetcher).to receive(:new).and_raise(ArgumentError, "at most 2 key pins")

    result = pull

    expect(result).to have_attributes(status: :failed, error: "The connection is not set up to pull: at most 2 key pins")
    expect(connection.reload.last_error).to eq("The connection is not set up to pull: at most 2 key pins")
    expect(ReceivedDocument.count).to eq(0)
  end

  it "reaches that refusal with the real fetcher when the stored pins are malformed" do
    allow(ExchangeFetcher).to receive(:new).and_call_original
    connection.update_columns(spki_sha256: [ "a" * 64, "b" * 64, "c" * 64 ])

    result = pull

    expect(result.status).to eq(:failed)
    expect(result.error).to start_with("The connection is not set up to pull:")
  end
end
