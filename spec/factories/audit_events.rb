# frozen_string_literal: true

FactoryBot.define do
  factory :audit_event do
    action { "login_success" }
    provider { "local" }
    ip_address { "127.0.0.1" }

    trait :with_user do
      association :user
    end

    trait :with_subject do
      subject_type { "SspDocument" }
      subject_id { 1 }
    end

    trait :resource_event do
      action { "ssp_document_created" }
      subject_type { "SspDocument" }
      subject_id { 1 }
    end
  end
end
