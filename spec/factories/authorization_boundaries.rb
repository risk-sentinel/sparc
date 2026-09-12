FactoryBot.define do
  factory :authorization_boundary do
    name { Faker::Company.name + " ATO" }
    description { Faker::Lorem.paragraph }
    status { "draft" }

    trait :active do
      status { "active" }
    end

    # #1040 — authorization now requires the accountable roles on the roster, so
    # the trait staffs the boundary. A trait that produces an invalid record is
    # a trap for whoever reaches for it next.
    trait :authorized do
      status { "authorized" }
      authorization_boundary_description { Faker::Lorem.paragraph }

      after(:build) do |ab|
        AuthorizationBoundary::REQUIRED_ROLES_FOR_AUTHORIZATION.each do |role|
          ab.authorization_boundary_memberships.build(
            role: role, user_name: Faker::Name.name, user_email: Faker::Internet.email
          )
        end
      end
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
