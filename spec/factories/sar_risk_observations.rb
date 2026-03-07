FactoryBot.define do
  factory :sar_risk_observation do
    association :sar_risk
    association :sar_observation
  end
end
