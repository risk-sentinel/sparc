FactoryBot.define do
  factory :authorization_boundary do
    name { Faker::Company.name + " ATO" }
    description { Faker::Lorem.paragraph }
    status { "draft" }

    trait :active do
      status { "active" }
    end

    trait :authorized do
      status { "authorized" }
      authorization_boundary_description { Faker::Lorem.paragraph }
    end

    trait :with_boundaries do
      after(:create) do |authorization_boundary|
        create(:boundary, authorization_boundary: authorization_boundary, name: "Production", environment: "production")
        create(:boundary, authorization_boundary: authorization_boundary, name: "Development", environment: "development")
      end
    end

    trait :with_members do
      after(:create) do |authorization_boundary|
        create(:authorization_boundary_membership, authorization_boundary: authorization_boundary, role: "system_owner")
        create(:authorization_boundary_membership, authorization_boundary: authorization_boundary, role: "isso")
      end
    end
  end
end
