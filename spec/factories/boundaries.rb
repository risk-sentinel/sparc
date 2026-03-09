FactoryBot.define do
  factory :boundary do
    association :authorization_boundary
    name { Faker::Lorem.words(number: 2).join(" ") + " Environment" }
    description { Faker::Lorem.sentence }
    environment { "production" }
  end
end
