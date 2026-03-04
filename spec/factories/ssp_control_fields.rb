FactoryBot.define do
  factory :ssp_control_field do
    association :ssp_control
    field_name { 'responsible_role' }
    field_value { Faker::Job.title }
    editable { true }
  end
end
