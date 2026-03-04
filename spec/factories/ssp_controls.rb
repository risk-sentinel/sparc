FactoryBot.define do
  factory :ssp_control do
    association :ssp_document
    control_id { "AC-#{Faker::Number.between(from: 1, to: 100)}" }
    title { Faker::Lorem.sentence }
  end
end
