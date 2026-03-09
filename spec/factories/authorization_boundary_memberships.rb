FactoryBot.define do
  factory :authorization_boundary_membership do
    association :authorization_boundary
    user_name { Faker::Name.name }
    user_email { Faker::Internet.email }
    role { "project_member" }
  end
end
