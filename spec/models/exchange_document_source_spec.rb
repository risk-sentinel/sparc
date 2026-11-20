# frozen_string_literal: true

require "rails_helper"

# #1354 — one document SPARC pulls from a connection: its https address, its
# format, and how often to pull it.
RSpec.describe ExchangeDocumentSource do
  include ActiveSupport::Testing::TimeHelpers

  let(:connection) { create(:exchange_connection) }

  def build_source(**attrs) = build(:exchange_document_source, exchange_connection: connection, **attrs)

  def errors_on(attribute, **attrs)
    source = build_source(**attrs)
    source.validate
    source.errors[attribute]
  end

  describe "validations" do
    it "is valid with an https address, a known format and an interval" do
      expect(build_source).to be_valid
    end

    it "takes https addresses only, with a host and no user name" do
      expect(errors_on(:url, url: "http://trust.provider.example/a.json")).to include("must be an https:// address")
      expect(errors_on(:url, url: "https://u:p@trust.provider.example/a.json")).to include("must be an https:// address")
      expect(errors_on(:url, url: "")).to include("must be an https:// address")
      expect(errors_on(:url, url: "https://exa mple.com/a.json")).to include("is not a valid address")
    end

    it "takes one of the four formats" do
      %w[fedramp oscal hdf xccdf].each { |f| expect(build_source(format: f)).to be_valid, f }
      expect(errors_on(:format, format: "docx")).to be_present
    end

    it "pulls between hourly and every 31 days, in whole hours" do
      expect(build_source(pull_interval_hours: 1)).to be_valid
      expect(build_source(pull_interval_hours: 24 * 31)).to be_valid
      expect(errors_on(:pull_interval_hours, pull_interval_hours: 0)).to be_present
      expect(errors_on(:pull_interval_hours, pull_interval_hours: 24 * 31 + 1)).to be_present
      expect(errors_on(:pull_interval_hours, pull_interval_hours: 1.5)).to be_present
    end

    it "registers an address once per connection, and the same address on another connection" do
      create(:exchange_document_source, exchange_connection: connection, url: "https://trust.provider.example/x.json")
      expect(errors_on(:url, url: "https://trust.provider.example/x.json")).to include("has already been taken")
      other = build(:exchange_document_source, exchange_connection: create(:exchange_connection),
                                               url: "https://trust.provider.example/x.json")
      expect(other).to be_valid
    end
  end

  describe "#due?" do
    let(:now) { Time.zone.parse("2026-11-20 12:00:00") }

    it "is due when never pulled" do
      expect(build_source(last_pulled_at: nil)).to be_due(now)
    end

    it "is due once its interval has passed, and not before" do
      expect(build_source(pull_interval_hours: 6, last_pulled_at: now - 6.hours)).to be_due(now)
      expect(build_source(pull_interval_hours: 6, last_pulled_at: now - 7.hours)).to be_due(now)
      expect(build_source(pull_interval_hours: 6, last_pulled_at: now - 5.hours - 59.minutes)).not_to be_due(now)
    end

    it "is never due when disabled" do
      expect(build_source(enabled: false, last_pulled_at: nil)).not_to be_due(now)
    end

    it "defaults to the current time" do
      travel_to(now) do
        expect(build_source(pull_interval_hours: 1, last_pulled_at: now - 2.hours)).to be_due
        expect(build_source(pull_interval_hours: 1, last_pulled_at: now - 30.minutes)).not_to be_due
      end
    end
  end

  it "has one stream per document address, keyed by its id" do
    source = create(:exchange_document_source, exchange_connection: connection)
    other = create(:exchange_document_source, exchange_connection: connection)
    expect(source.stream_key).to eq("pull:source:#{source.id}")
    expect(other.stream_key).not_to eq(source.stream_key)
  end

  it ".enabled lists only enabled sources" do
    on = create(:exchange_document_source, exchange_connection: connection)
    create(:exchange_document_source, exchange_connection: connection, enabled: false)
    expect(described_class.enabled).to eq([ on ])
  end
end
