FactoryBot.define do
  factory :control_family do
    association :control_catalog
    sequence(:code) { |n| "F#{n.to_s.rjust(2, '0')}" }
    name { Faker::Lorem.words(number: 2).join(" ").titleize }
    sort_order { 1 }
  end
end
