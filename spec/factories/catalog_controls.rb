FactoryBot.define do
  factory :catalog_control do
    control_family
    sequence(:control_id) { |n| "#{control_family&.code || 'AC'}-#{n.to_s.rjust(2, '0')}" }
    title { Faker::Lorem.sentence }
    priority { %w[P0 P1 P2 P3].sample }
    baseline_impact { "LOW, MODERATE, HIGH" }
    guidance_data { {} }
  end
end
