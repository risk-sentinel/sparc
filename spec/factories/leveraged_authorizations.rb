FactoryBot.define do
  factory :leveraged_authorization do
    leveraging_boundary { association(:authorization_boundary) }
    leveraged_boundary  { association(:authorization_boundary) }
    sequence(:name) { |n| "Leveraged System #{n}" }
    crm_type { "oscal_with_access" }
    date_authorized { Date.today }
    description { Faker::Lorem.paragraph }

    trait :oscal_no_access do
      crm_type { "oscal_no_access" }
      leveraged_boundary { nil }
    end

    trait :legacy do
      crm_type { "legacy" }
      leveraged_boundary { nil }
    end
  end
end
