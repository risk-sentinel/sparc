# frozen_string_literal: true

FactoryBot.define do
  factory :user_role do
    user
    role
    authorization_boundary_id { nil }
  end
end
