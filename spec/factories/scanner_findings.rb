FactoryBot.define do
  factory :scanner_finding do
    association :scan_run
    authorization_boundary { scan_run.authorization_boundary }
    sequence(:control_id) { |n| "CVE-2026-#{format('%04d', n)}" }
    status { "failed" }
    severity { "HIGH" }
    title { Faker::Lorem.sentence(word_count: 6) }
    description { Faker::Lorem.paragraph }
    scanner { "trivy" }
    raw_hdf { { "id" => control_id, "status" => status } }

    trait :failed do
      status { "failed" }
    end

    trait :passed do
      status { "passed" }
    end

    trait :critical do
      severity { "CRITICAL" }
    end
  end
end
