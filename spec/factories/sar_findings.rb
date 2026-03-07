FactoryBot.define do
  factory :sar_finding do
    association :sar_result
    uuid { SecureRandom.uuid }
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    target_data do
      {
        "type" => "objective-id",
        "target-id" => "ac-1",
        "status" => { "state" => "not-satisfied" }
      }
    end
  end
end
