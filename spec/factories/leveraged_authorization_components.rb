FactoryBot.define do
  factory :leveraged_authorization_component do
    leveraged_authorization
    sequence(:title) { |n| "Leveraged Component #{n}" }
    component_type { "this-system" }
    description { Faker::Lorem.sentence }
  end
end
