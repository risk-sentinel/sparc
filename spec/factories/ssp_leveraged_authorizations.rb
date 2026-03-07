FactoryBot.define do
  factory :ssp_leveraged_authorization do
    ssp_document
    uuid { SecureRandom.uuid }
    title { Faker::Lorem.words(number: 3).join(" ") }
    party_uuid { SecureRandom.uuid }
    date_authorized { Date.today }
  end
end
