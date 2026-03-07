FactoryBot.define do
  factory :sar_observation do
    association :sar_result
    uuid { SecureRandom.uuid }
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    collected { Time.current }
    methods_data { [ "TEST" ] }
  end
end
