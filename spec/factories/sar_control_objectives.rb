FactoryBot.define do
  factory :sar_control_objective do
    sar_control
    sequence(:objective_id) { |n| "ac-1_obj.a-#{n}" }
    sequence(:label) { |n| "AC-01a.[#{n.to_s.rjust(2, '0')}]" }
    prose { Faker::Lorem.sentence }
    status { "pending" }
    sequence(:row_order) { |n| n }
    uuid { SecureRandom.uuid }
  end
end
