FactoryBot.define do
  factory :finding_disposition do
    association :authorization_boundary
    sequence(:control_id) { |n| "CVE-2026-#{format('%04d', n)}" }
    kind { "poam" }
    reason { Faker::Lorem.paragraph }
    decided_by { Faker::Internet.email }
    decided_at { Time.current }
    # Every override SPARC exports must carry an expiresAt (hdf-libs 3.7.0
    # requires it on all kinds), and a disposition may not park a finding for
    # more than FindingDisposition::MAX_EXPIRATION_WINDOW. A default review
    # date makes the factory produce a disposition that can actually be
    # exported; specs that care about its absence set `expiration: nil`.
    expiration { 90.days.from_now }
    # #1368 — the NIST POA&M fields every disposition decided now carries.
    nist_risk_prop { kind == "falsePositive" ? "false-positive" : "accepted" }
    nist_risk_status { "deviation-requested" }
    nist_response_lifecycle { "planned" }
    nist_facet_state { "initial" }
    nist_likelihood { "moderate" }
    nist_impact { "high" }

    trait :false_positive do
      kind { "falsePositive" }
    end

    trait :attestation do
      kind { "attestation" }
      association :linked_subject, factory: :attestation
    end

    # A disposition decided before v1.17.9 recorded its NIST fields.
    trait :without_nist do
      nist_risk_prop { nil }
      nist_risk_status { nil }
      nist_response_lifecycle { nil }
      nist_facet_state { nil }
      nist_likelihood { nil }
      nist_impact { nil }
    end

    trait :waiver do
      kind { "waiver" }
      expiration { 90.days.from_now }
    end

    trait :operational_requirement do
      kind { "operationalRequirement" }
      expiration { 90.days.from_now }
    end

    trait :risk_adjustment do
      kind { "riskAdjustment" }
      # #1368 — hdf-cli 3.8.0 requires the re-rated impact on this override.
      adjusted_impact { 0.3 }
      association :linked_subject, factory: :risk_assessment
    end
  end
end
