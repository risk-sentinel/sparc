FactoryBot.define do
  factory :profile_control_field do
    profile_control
    field_name { "description" }
    field_value { Faker::Lorem.paragraph }
    editable { false }
  end
end
