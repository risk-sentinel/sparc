# frozen_string_literal: true

FactoryBot.define do
  factory :organization_membership do
    organization
    user
    role { "member" }

    trait :org_admin do
      role { "org_admin" }
    end

    trait :ciso do
      role { "ciso" }
    end

    trait :cio do
      role { "cio" }
    end
  end
end
