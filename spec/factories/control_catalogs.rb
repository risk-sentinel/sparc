FactoryBot.define do
  factory :control_catalog do
    name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    version { "1.0.0" }
    source { "OSCAL" }
    lifecycle_status { "published" }
    oscal_version { "1.1.2" }
    metadata_extra { {} }

    trait :with_metadata do
      published { "2024-06-01T00:00:00Z" }
      metadata_extra do
        {
          "roles" => [ { "id" => "prepared-by", "title" => "Prepared By" } ],
          "parties" => [ { "uuid" => SecureRandom.uuid, "type" => "organization", "name" => "Test Org" } ]
        }
      end
    end

    trait :with_families do
      after(:create) do |catalog|
        create_list(:control_family, 2, control_catalog: catalog)
      end
    end
  end
end
