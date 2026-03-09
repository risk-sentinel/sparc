FactoryBot.define do
  factory :control_mapping_entry do
    sequence(:source_control_id) { |n| "AC-#{n}" }
    sequence(:target_control_id) { |n| "A.5.#{n}" }
    relationship { "equivalent" }
    source_type { "control" }
    target_type { "control" }
    association :control_mapping
  end
end
