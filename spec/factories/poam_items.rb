FactoryBot.define do
  factory :poam_item do
    poam_document
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    poam_item_uuid { SecureRandom.uuid }
    risk_status { %w[open investigating remediating deviation-requested deviation-approved closed].sample }
    impact { %w[high medium low].sample }
    likelihood { %w[high medium low].sample }
    row_order { 0 }
  end
end
