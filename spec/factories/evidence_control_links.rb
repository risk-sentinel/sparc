FactoryBot.define do
  factory :evidence_control_link do
    association :evidence
    sequence(:control_id) { |n| "AC-#{n.to_s.rjust(2, '0')}" }
    document_type { nil }
    document_id { nil }
  end
end
