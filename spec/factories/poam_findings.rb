FactoryBot.define do
  factory :poam_finding do
    poam_document
    uuid { SecureRandom.uuid }
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
  end
end
