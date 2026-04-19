FactoryBot.define do
  factory :cdef_control_statement do
    cdef_control
    sequence(:statement_id) { |n| "ac-1_smt.#{('a'..'z').to_a[(n - 1) % 26]}" }
    sequence(:label) { |n| "AC-01#{('a'..'z').to_a[(n - 1) % 26]}." }
    implementation_prose { Faker::Lorem.sentence }
    sequence(:row_order) { |n| n }
    uuid { SecureRandom.uuid }
  end
end
