FactoryBot.define do
  factory :sar_document do
    # #952 — an SSP/SAP/SAR/POA&M must belong to an authorization boundary: a
    # boundary-less one was treated as instance-wide and shown to EVERY signed-in
    # user. Associated here rather than in ~150 spec files. A spec that needs a
    # LEGACY boundary-less row (they exist on upgraded instances) builds it with
    # `create_legacy_orphan`, which saves without validation.
    association :authorization_boundary
    name { Faker::Lorem.sentence(word_count: 3) }
    file_type { "excel" }
    status { "completed" }
    lifecycle_status { "in_progress" }
    original_filename { "test_sar.xlsx" }
    creation_method { "excel" }

    trait :wizard do
      creation_method { "wizard" }
      file_type { "json" }
      original_filename { nil }
    end

    trait :oscal_import do
      creation_method { "oscal_import" }
      file_type { "json" }
      original_filename { "assessment-results.json" }
    end

    trait :enriched do
      description { Faker::Lorem.paragraph }
      import_ap_href { "#assessment-plan-uuid" }
      assessment_start { 1.month.ago }
      assessment_end { Time.current }
    end
  end
end
