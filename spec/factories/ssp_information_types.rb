FactoryBot.define do
  factory :ssp_information_type do
    ssp_document
    uuid { SecureRandom.uuid }
    title { Faker::Lorem.words(number: 3).join(" ") }
    description { Faker::Lorem.sentence }
  end
end
