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

    # The evidence is created in the SAME boundary as the validation. A bare
    # `association :evidence` builds one with no boundary at all, which #851
    # makes invalid — a trait that produces an unsaveable record is a trap for
    # whoever reaches for it next.
    trait :with_evidence do
      after(:build) do |validation|
        validation.evidence ||= build(:evidence, authorization_boundary: validation.authorization_boundary)
      end
    end

    # Deliberately invalid: evidence belonging to a DIFFERENT boundary, for
    # exercising the #851 cross-boundary guard.
    trait :with_foreign_evidence do
      after(:build) do |validation|
        validation.evidence ||= build(:evidence, authorization_boundary: build(:authorization_boundary))
      end
    end

    trait :with_metadata do
      validation_metadata { { tool: "Trivy", scan_id: SecureRandom.hex(8), score: 95 } }
    end
  end
end
