FactoryBot.define do
  factory :scan_run do
    association :authorization_boundary
    scanner { %w[trivy brakeman gitleaks].sample }
    scanner_version { "1.0.0" }
    ingested_at { Time.current }
    finding_count { 0 }
    passed_count { 0 }
    failed_count { 0 }
    skipped_count { 0 }
    source_filename { "scan.hdf.json" }
    created_by { Faker::Internet.email }

    trait :with_findings do
      after(:create) do |scan_run|
        create(:scanner_finding, :failed, scan_run: scan_run,
               authorization_boundary: scan_run.authorization_boundary)
        create(:scanner_finding, scan_run: scan_run,
               authorization_boundary: scan_run.authorization_boundary,
               control_id: "CVE-2026-0002", status: "passed")
      end
    end
  end
end
