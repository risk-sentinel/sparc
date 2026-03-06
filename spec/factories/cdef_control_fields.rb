FactoryBot.define do
  factory :cdef_control_field do
    cdef_control
    field_name { "description" }
    field_value { Faker::Lorem.paragraph }
    editable { false }
  end
end
