FactoryBot.define do
  factory :ksi_validation do
    authorization_boundary
    catalog_control
    status { "not_assessed" }

    trait :passed do
      status { "passed" }
      validation_method { "automated" }
      last_validated_at { 1.day.ago }
      next_validation_due { 6.days.from_now }
    end

    trait :failed do
      status { "failed" }
      validation_method { "automated" }
      last_validated_at { 1.day.ago }
    end

    trait :expired do
      status { "expired" }
      last_validated_at { 2.weeks.ago }
      next_validation_due { 1.week.ago }
    end

    trait :overdue do
      status { "passed" }
      last_validated_at { 2.weeks.ago }
      next_validation_due { 1.day.ago }
    end

    trait :with_evidence do
      association :evidence
    end

    trait :with_metadata do
      validation_metadata { { tool: "Trivy", scan_id: SecureRandom.hex(8), score: 95 } }
    end
  end
end
