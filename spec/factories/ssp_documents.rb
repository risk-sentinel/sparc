FactoryBot.define do
  factory :ssp_document do
    name { Faker::Lorem.words(number: 3).join(" ") }
    file_type { "excel" }
    status { "completed" }
    lifecycle_status { "in_progress" }
    original_filename { "#{name}.xlsx" }

    trait :wizard do
      creation_method { "wizard" }
      file_type { nil }
      original_filename { nil }
    end

    trait :oscal_import do
      creation_method { "oscal_import" }
      file_type { "json" }
      original_filename { "#{name}.json" }
    end

    trait :enriched do
      description { Faker::Lorem.paragraph }
      security_sensitivity_level { "fips-199-moderate" }
      system_status { "operational" }
      security_objective_confidentiality { "fips-199-moderate" }
      security_objective_integrity { "fips-199-moderate" }
      security_objective_availability { "fips-199-low" }
      authorization_boundary_description { "Test authorization boundary." }
    end
  end
end
