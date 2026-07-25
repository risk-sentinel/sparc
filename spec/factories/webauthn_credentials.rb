# frozen_string_literal: true

FactoryBot.define do
  factory :webauthn_credential do
    association :user
    sequence(:external_id) { |n| "ext-credential-#{n}-#{SecureRandom.hex(4)}" }
    public_key { "pk_#{SecureRandom.hex(16)}" }
    sign_count { 0 }
    nickname { "Test Security Key" }
  end
end
