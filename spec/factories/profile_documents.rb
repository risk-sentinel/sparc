FactoryBot.define do
  factory :profile_document do
    name { Faker::Lorem.words(number: 3).join(" ") }
    file_type { "json" }
    status { "completed" }
    lifecycle_status { "in_progress" }
    original_filename { "#{Faker::File.file_name(ext: 'json')}" }
    baseline_level { %w[LOW MODERATE HIGH].sample }
    profile_version { "1.0.0" }
    oscal_version { "1.1.2" }
  end
end
