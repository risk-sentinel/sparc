FactoryBot.define do
  factory :poam_item do
    poam_document
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    risk_status { %w[open deviation-approved closed].sample }
    impact { %w[high medium low].sample }
    likelihood { %w[high medium low].sample }
    row_order { 0 }
  end
end
