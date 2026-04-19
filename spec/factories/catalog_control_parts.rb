FactoryBot.define do
  factory :catalog_control_part do
    catalog_control
    sequence(:part_id) { |n| "ac-1_smt.#{('a'..'z').to_a[(n - 1) % 26]}" }
    part_name { "statement" }
    sequence(:label) { |n| "AC-01#{('a'..'z').to_a[(n - 1) % 26]}." }
    prose { Faker::Lorem.sentence }
    sequence(:row_order) { |n| n }
    uuid { SecureRandom.uuid }
  end
end
