FactoryBot.define do
  factory :sar_control do
    control_id { "AC-#{rand(1..20)}" }
    title { Faker::Lorem.sentence(word_count: 4) }
    association :sar_document
    section { "Sheet1" }
    row_order { 0 }
  end
end
