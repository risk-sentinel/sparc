FactoryBot.define do
  factory :sap_control_field do
    sap_control
    field_name { "objective" }
    field_value { Faker::Lorem.paragraph }
    editable { true }
  end
end
