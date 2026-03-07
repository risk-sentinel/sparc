FactoryBot.define do
  factory :poam_observation do
    poam_document
    uuid { SecureRandom.uuid }
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    collected { Time.current }
  end
end
