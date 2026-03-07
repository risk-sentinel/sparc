FactoryBot.define do
  factory :poam_milestone do
    poam_remediation
    uuid { SecureRandom.uuid }
    milestone_type { "milestone" }
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    due_date { 30.days.from_now.to_date }
    position { 0 }
  end
end
