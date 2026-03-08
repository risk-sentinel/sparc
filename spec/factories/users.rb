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
  end
end
