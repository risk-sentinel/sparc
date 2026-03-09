# frozen_string_literal: true

FactoryBot.define do
  factory :role do
    sequence(:name) { |n| "role_#{n}" }
    sequence(:display_name) { |n| "Role #{n}" }
    scope { "instance" }
    sort_order { 0 }

    trait :authorization_boundary_scoped do
      scope { "authorization_boundary" }
    end
  end
end
