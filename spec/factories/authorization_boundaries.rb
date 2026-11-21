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

    # #1390 — every field the FedRAMP Certification Package Overview requires,
    # and its Security and Sales contacts.
    trait :fedramp_overview_ready do
      fedramp_package do
        { "package_id" => "FR2400000001", "provider_name" => "Example Provider", "service_name" => "Example Cloud",
          "service_acronym" => "EXC", "service_description" => "A cloud service.", "certification_type" => "20x",
          "website" => "https://provider.example", "logo" => "https://provider.example/logo.png",
          "service_types" => [ "SaaS" ], "deployment_model" => "Public Cloud" }
      end
      fedramp_contacts do
        [ { "contact_type" => "Security", "name" => "Security Team", "email" => "security@provider.example" },
          { "contact_type" => "Sales", "name" => "Sales Team", "phone" => "202-555-0123" } ]
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
