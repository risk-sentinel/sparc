FactoryBot.define do
  factory :poam_item do
    poam_document
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    poam_item_uuid { SecureRandom.uuid }
    risk_status { %w[open investigating remediating deviation-requested deviation-approved closed].sample }
    # #1095 — the five-level scale, from the one constant that defines it.
    # This still generated the pre-#1090 three-level list, so every factory-built
    # POA&M item re-seeded the legacy "medium" the data migration had just
    # removed.
    impact { RiskRating::LEVELS.sample }
    likelihood { RiskRating::LEVELS.sample }
    row_order { 0 }
  end
end
