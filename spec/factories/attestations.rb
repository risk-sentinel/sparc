FactoryBot.define do
  factory :attestation do
    association :evidence
    attester_name { Faker::Name.name }
    attester_email { Faker::Internet.email }
    role { "assessor" }
    statement { Faker::Lorem.paragraph(sentence_count: 3) }
    attested_at { Time.current }
  end
end
