FactoryBot.define do
  factory :poam_document do
    name { "#{Faker::Company.name} POA&M" }
    file_type { "json" }
    original_filename { "poam_#{Date.today}.json" }
    status { "completed" }
  end
end
