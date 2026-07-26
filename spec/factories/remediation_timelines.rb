FactoryBot.define do
  factory :remediation_timeline do
    baseline_level { "Moderate" }
    criticality { "High" }
    days { 30 }
    updated_by { "admin@sparc.local" }
  end
end
