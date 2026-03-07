FactoryBot.define do
  factory :sap_control do
    control_id { "AC-#{Faker::Number.between(from: 1, to: 22)}" }
    title { Faker::Lorem.sentence }
    assessment_method { %w[examine interview test].sample }
    assessment_status { "planned" }
    sap_document
  end
end
