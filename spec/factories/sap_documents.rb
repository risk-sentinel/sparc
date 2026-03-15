FactoryBot.define do
  factory :sap_document do
    name { Faker::Lorem.words(number: 3).join(" ") }
    status { "completed" }
    lifecycle_status { "in_progress" }
    assessment_type { "initial" }
    assessment_start { Date.today }
    assessment_end { Date.today + 30 }
  end
end
