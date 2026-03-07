FactoryBot.define do
  factory :sar_finding_observation do
    association :sar_finding
    association :sar_observation
  end
end
