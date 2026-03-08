# frozen_string_literal: true

FactoryBot.define do
  factory :audit_event do
    action { "login_success" }
    provider { "local" }
    ip_address { "127.0.0.1" }
  end
end
