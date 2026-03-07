FactoryBot.define do
  factory :poam_remediation do
    poam_risk
    uuid { SecureRandom.uuid }
    lifecycle { "planned" }
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    position { 0 }
  end
end
