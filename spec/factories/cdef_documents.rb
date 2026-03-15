FactoryBot.define do
  factory :cdef_document do
    name { Faker::Lorem.words(number: 3).join(" ") }
    file_type { %w[xccdf json].sample }
    status { "completed" }
    lifecycle_status { "in_progress" }
    original_filename { "#{Faker::File.file_name(ext: 'xml')}" }
    cdef_type { %w[disa_stig scap cis custom].sample }
  end
end
