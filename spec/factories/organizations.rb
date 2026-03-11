# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    name { Faker::Company.unique.name }
    description { Faker::Lorem.paragraph }
    status { "active" }

    trait :inactive do
      status { "inactive" }
    end

    trait :with_contact do
      contact_person { Faker::Name.name }
      contact_email { Faker::Internet.email }
      address { Faker::Address.full_address }
    end

    trait :with_members do
      after(:create) do |organization|
        create(:organization_membership, organization: organization, role: "org_admin")
        create(:organization_membership, organization: organization, role: "member")
      end
    end
  end
end
