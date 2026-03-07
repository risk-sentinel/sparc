FactoryBot.define do
  factory :project do
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
      after(:create) do |project|
        create(:boundary, project: project, name: "Production", environment: "production")
        create(:boundary, project: project, name: "Development", environment: "development")
      end
    end

    trait :with_members do
      after(:create) do |project|
        create(:project_membership, project: project, role: "system_owner")
        create(:project_membership, project: project, role: "isso")
      end
    end
  end
end
