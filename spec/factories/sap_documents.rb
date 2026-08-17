FactoryBot.define do
  factory :sap_document do
    # #952 — an SSP/SAP/SAR/POA&M must belong to an authorization boundary: a
    # boundary-less one was treated as instance-wide and shown to EVERY signed-in
    # user. Associated here rather than in ~150 spec files. A spec that needs a
    # LEGACY boundary-less row (they exist on upgraded instances) builds it with
    # `create_legacy_orphan`, which saves without validation.
    association :authorization_boundary
    name { Faker::Lorem.words(number: 3).join(" ") }
    status { "completed" }
    lifecycle_status { "in_progress" }
    assessment_type { "initial" }
    assessment_start { Date.today }
    assessment_end { Date.today + 30 }
  end
end
