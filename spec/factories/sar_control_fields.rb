FactoryBot.define do
  factory :sar_control_field do
    association :sar_control
    field_name { "result" }
    field_value { "Pass" }
    editable { true }
  end
end
