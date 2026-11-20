# frozen_string_literal: true

require "rails_helper"

# #1354 — the hourly pull: each due document of each enabled connection; with
# an id, that one document now. One document's failure never stops the others.
RSpec.describe ExchangePullJob do
  let(:boundary) { create(:authorization_boundary) }
  let(:connection) { create(:exchange_connection, authorization_boundary: boundary) }
  let(:fetcher) { instance_double(ExchangeFetcher) }

  def vdr(n)
    { "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
      "reportPeriod" => { "from" => "2026-10-01T00:00:00Z", "to" => "2026-10-#{10 + n}T23:59:59Z" },
      "vulnerabilities" => [] }.to_json
  end

  def source(on: connection, **attrs) = create(:exchange_document_source, exchange_connection: on, **attrs)

  def respond_with(src, body)
    allow(fetcher).to receive(:get).with(src.url).and_return(
      ExchangeFetcher::Result.new(body: body, content_type: "application/json", final_url: src.url, peer_ip: "203.0.113.1",
                                  spki_sha256: nil, status: 200, bytes: body.bytesize, sha256: Digest::SHA256.hexdigest(body))
    )
  end

  before { allow(ExchangeFetcher).to receive(:new).and_return(fetcher) }

  describe "with a document source id" do
    it "pulls that one document now, even when it is not due, as the user who asked" do
      user = create(:user)
      wanted = source(last_pulled_at: 1.minute.ago)
      other = source
      respond_with(wanted, vdr(1))
      allow(ExchangePullService).to receive(:call).and_call_original

      described_class.perform_now(wanted.id, user.id)

      expect(ExchangePullService).to have_received(:call).once.with(wanted, user: user)
      expect(wanted.reload.last_status).to eq("stored")
      expect(other.reload.last_pulled_at).to be_nil
      expect(AuditEvent.find_by!(action: "exchange_pull_completed").user).to eq(user)
    end

    it "does nothing for a source that no longer exists" do
      allow(ExchangePullService).to receive(:call)
      expect { described_class.perform_now(0) }.not_to raise_error
      expect(ExchangePullService).not_to have_received(:call)
    end
  end

  describe "the scheduled run" do
    it "pulls only due, enabled documents of enabled connections" do
      due = source(last_pulled_at: nil)
      overdue = source(pull_interval_hours: 1, last_pulled_at: 2.hours.ago)
      not_due = source(pull_interval_hours: 24, last_pulled_at: 1.hour.ago)
      disabled_source = source(enabled: false)
      off_connection = create(:exchange_connection, authorization_boundary: boundary, enabled: false)
      on_disabled_connection = source(on: off_connection)
      allow(ExchangePullService).to receive(:call)

      described_class.perform_now

      expect(ExchangePullService).to have_received(:call).with(due)
      expect(ExchangePullService).to have_received(:call).with(overdue)
      expect(ExchangePullService).to have_received(:call).twice
      [ not_due, disabled_source, on_disabled_connection ].each do |skipped|
        expect(ExchangePullService).not_to have_received(:call).with(skipped)
      end
    end

    it "keeps pulling the others when one document's fetch fails" do
      failing = source
      working = source
      allow(fetcher).to receive(:get).with(failing.url).and_raise(ExchangeFetcher::Error.new(:timeout, "did not answer"))
      respond_with(working, vdr(2))

      described_class.perform_now

      expect(failing.reload).to have_attributes(last_status: "failed", last_error: "did not answer")
      expect(working.reload.last_status).to eq("stored")
      expect(ReceivedDocument.where(exchange_document_source: working).count).to eq(1)
    end

    it "keeps pulling the others when one document's pull raises unexpectedly, and reports the error" do
      first, second = source, source
      allow(ExchangePullService).to receive(:call).and_call_original
      allow(ExchangePullService).to receive(:call).with(first).and_raise(RuntimeError, "boom")
      respond_with(second, vdr(3))
      allow(Rails.error).to receive(:report)

      expect { described_class.perform_now }.not_to raise_error

      expect(second.reload.last_status).to eq("stored")
      expect(Rails.error).to have_received(:report).with(an_instance_of(RuntimeError), hash_including(handled: true))
    end
  end
end
