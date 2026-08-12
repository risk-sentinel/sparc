# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }
    password { "SecurePassword123!" }
    password_confirmation { "SecurePassword123!" }
    display_name { Faker::Name.name }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    status { "active" }
    admin { false }
    must_reset_password { false }

    trait :admin do
      admin { true }
    end

    trait :suspended do
      status { "suspended" }
    end

    trait :must_reset do
      must_reset_password { true }
    end

    trait :oauth_only do
      password { nil }
      password_confirmation { nil }
      password_digest { nil }
    end

    trait :deactivated do
      status { "deactivated" }
      deleted_at { Time.current }
      inactive_reason { "admin_action" }
    end

    trait :auto_deactivated do
      status { "deactivated" }
      deleted_at { Time.current }
      inactive_reason { "auto_inactivity" }
    end

    trait :with_expired_password do
      password_changed_at { 60.days.ago }
    end

    # A service account is a real User row, not a separate kind of principal —
    # which is why an API token minted for one resolves to it as `current_user`
    # and why evidence it submits is attributed to it (#934). `owner` is
    # required by the model, so the trait supplies one rather than leaving the
    # record invalid.
    trait :service_account do
      service_account { true }
      display_name { "Pipeline Service Account" }
      association :owner, factory: :user
    end
  end
end
