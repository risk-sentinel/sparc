# frozen_string_literal: true

# #1354 — a connection to another system's trust center, the documents it
# pulls, and the versions a boundary received.
FactoryBot.define do
  factory :exchange_connection do
    sequence(:name) { |n| "Provider #{n}" }
    authorization_boundary
    root_url { "https://trust.provider.example/" }
    auth_scheme { "none" }
  end

  factory :exchange_document_source do
    exchange_connection
    sequence(:url) { |n| "https://trust.provider.example/package/document-#{n}.json" }
    format { "fedramp" }
    document_type { "vulnerability-detail-report" }
    pull_interval_hours { 24 }
  end

  factory :received_document do
    authorization_boundary
    source { "upload" }
    sequence(:stream_key) { |n| "upload:spec-stream-#{n}" }
    format { "fedramp" }
    document_type { "vulnerability-detail-report" }
    sha256 { SecureRandom.hex(32) }
    byte_size { 10 }
    state { "pending_review" }
    valid_document { true }
    received_at { Time.current }
  end
end
