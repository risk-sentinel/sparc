FactoryBot.define do
  factory :sar_result do
    association :sar_document
    uuid { SecureRandom.uuid }
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    start_time { 1.month.ago }
    end_time { Time.current }
    position { 0 }
  end
end
