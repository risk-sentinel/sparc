FactoryBot.define do
  factory :ssp_inventory_item do
    ssp_document
    uuid { SecureRandom.uuid }
    description { Faker::Lorem.sentence }
  end
end
