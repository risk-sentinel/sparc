FactoryBot.define do
  factory :control_family do
    association :control_catalog
    sequence(:code) { |n| ("AA".."ZZ").to_a[n % 676] }
    name { Faker::Lorem.words(number: 2).join(" ").titleize }
    sort_order { 1 }
  end
end
