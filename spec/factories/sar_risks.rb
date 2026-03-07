FactoryBot.define do
  factory :sar_risk do
    association :sar_result
    uuid { SecureRandom.uuid }
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    statement { Faker::Lorem.paragraph }
    status { "open" }
  end
end
