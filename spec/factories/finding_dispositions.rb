FactoryBot.define do
  factory :finding_disposition do
    association :authorization_boundary
    sequence(:control_id) { |n| "CVE-2026-#{format('%04d', n)}" }
    kind { "poam" }
    reason { Faker::Lorem.paragraph }
    decided_by { Faker::Internet.email }
    decided_at { Time.current }
    # Every override SPARC exports must carry an expiresAt (hdf-libs 3.7.0
    # requires it on all kinds), and a disposition may not park a finding for
    # more than FindingDisposition::MAX_EXPIRATION_WINDOW. A default review
    # date makes the factory produce a disposition that can actually be
    # exported; specs that care about its absence set `expiration: nil`.
    expiration { 90.days.from_now }

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
