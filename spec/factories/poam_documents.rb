FactoryBot.define do
  factory :poam_document do
    # #952 — an SSP/SAP/SAR/POA&M must belong to an authorization boundary: a
    # boundary-less one was treated as instance-wide and shown to EVERY signed-in
    # user. Associated here rather than in ~150 spec files. A spec that needs a
    # LEGACY boundary-less row (they exist on upgraded instances) builds it with
    # `create_legacy_orphan`, which saves without validation.
    association :authorization_boundary
    name { "#{Faker::Company.name} POA&M" }
    file_type { "json" }
    original_filename { "poam_#{Date.today}.json" }
    status { "completed" }
    lifecycle_status { "in_progress" }
  end
end
