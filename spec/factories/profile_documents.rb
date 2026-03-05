FactoryBot.define do
  factory :profile_document do
    name { Faker::Lorem.words(number: 3).join(" ") }
    file_type { %w[xccdf json].sample }
    status { "completed" }
    original_filename { "#{Faker::File.file_name(ext: 'xml')}" }
    profile_type { %w[disa_stig scap cis custom].sample }
  end
end
