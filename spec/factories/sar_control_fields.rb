FactoryBot.define do
  factory :sar_control_field do
    sar_control { nil }
    field_name { "MyString" }
    field_value { "MyText" }
    editable { false }
  end
end
