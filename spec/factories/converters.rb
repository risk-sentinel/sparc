FactoryBot.define do
  factory :converter do
    sequence(:name) { |n| "Converter #{n}" }
    converter_type { "cci_to_nist" }
    status { "draft" }
    source_framework { "DISA CCI" }
    target_framework { "NIST SP 800-53" }
  end
end
