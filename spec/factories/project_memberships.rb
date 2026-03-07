FactoryBot.define do
  factory :project_membership do
    association :project
    user_name { Faker::Name.name }
    user_email { Faker::Internet.email }
    role { "project_member" }
  end
end
