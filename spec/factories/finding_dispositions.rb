FactoryBot.define do
  factory :finding_disposition do
    association :authorization_boundary
    sequence(:control_id) { |n| "CVE-2026-#{format('%04d', n)}" }
    kind { "poam" }
    reason { Faker::Lorem.paragraph }
    decided_by { Faker::Internet.email }
    decided_at { Time.current }

    trait :false_positive do
      kind { "falsePositive" }
    end

    trait :waiver do
      kind { "waiver" }
      expiration { 90.days.from_now }
    end

    trait :operational_requirement do
      kind { "operationalRequirement" }
      expiration { 90.days.from_now }
    end

    trait :risk_adjustment do
      kind { "riskAdjustment" }
      association :linked_subject, factory: :risk_assessment
    end
  end
end
