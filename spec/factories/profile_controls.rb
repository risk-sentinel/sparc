FactoryBot.define do
  factory :profile_control do
    control_id { "AC-#{Faker::Number.between(from: 1, to: 22)}" }
    title { Faker::Lorem.sentence }
    priority { %w[P1 P2 P3].sample }
    profile_document
  end
end
