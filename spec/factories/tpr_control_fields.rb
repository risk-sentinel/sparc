FactoryBot.define do
  factory :tpr_control_field do
    tpr_control { nil }
    field_name { "MyString" }
    field_value { "MyText" }
    editable { false }
  end
end
