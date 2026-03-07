FactoryBot.define do
  factory :poam_risk do
    poam_document
    uuid { SecureRandom.uuid }
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    status { %w[open investigating remediating deviation-requested deviation-approved closed].sample }
    likelihood { %w[high medium low].sample }
    impact { %w[high medium low].sample }
  end
end
