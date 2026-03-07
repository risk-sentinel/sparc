FactoryBot.define do
  factory :poam_item_field do
    poam_item
    field_name { "internal_notes" }
    field_value { Faker::Lorem.sentence }
    editable { true }
  end
end
