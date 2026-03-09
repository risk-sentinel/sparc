FactoryBot.define do
  factory :control_mapping do
    name { "#{Faker::Lorem.word.capitalize} to #{Faker::Lorem.word.capitalize} Mapping" }
    status { "draft" }
    method_type { "human" }
    matching_rationale { "semantic" }
    mapping_version { "1.0.0" }
    association :source_catalog, factory: :control_catalog
    association :target_catalog, factory: :control_catalog

    trait :complete do
      status { "complete" }
    end

    trait :deprecated do
      status { "deprecated" }
    end
  end
end
