FactoryBot.define do
  factory :evidence do
    title { Faker::Lorem.sentence(word_count: 3) }
    evidence_type { "artifact" }
    status { "draft" }
    description { Faker::Lorem.paragraph }
    collected_by { Faker::Name.name }
    collected_at { Time.current }
    source { Faker::Internet.url }

    trait :with_authorization_boundary do
      association :authorization_boundary
    end

    trait :collected do
      status { "collected" }
    end

    trait :attested do
      status { "attested" }
    end

    trait :scan_result do
      evidence_type { "scan_result" }
    end

    trait :policy_document do
      evidence_type { "policy_document" }
    end
  end
end
