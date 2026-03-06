FactoryBot.define do
  factory :ssp_document do
    name { Faker::Lorem.words(number: 3).join(' ') }
    file_type { 'excel' }
    status { 'completed' }
    original_filename { "#{name}.xlsx" }
  end
end
