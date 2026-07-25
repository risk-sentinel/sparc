FactoryBot.define do
  factory :risk_assessment do
    association :authorization_boundary
    title { Faker::Lorem.sentence(word_count: 4) }
    original_severity { "HIGH" }
    adjusted_severity { "LOW" }
    rationale { Faker::Lorem.paragraph }
    methodology { "CVSS environmental" }
    assessed_by { Faker::Name.name }
    assessed_at { Time.current }
    expiration { 90.days.from_now }
  end
end
