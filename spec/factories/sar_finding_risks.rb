FactoryBot.define do
  factory :sar_finding_risk do
    association :sar_finding
    association :sar_risk
  end
end
