# frozen_string_literal: true

FactoryBot.define do
  factory :identity do
    user
    provider { "github" }
    sequence(:uid) { |n| "uid_#{n}" }
    email { user.email }
  end
end
