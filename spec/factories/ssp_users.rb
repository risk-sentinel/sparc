FactoryBot.define do
  factory :ssp_user do
    ssp_document
    uuid { SecureRandom.uuid }
    title { Faker::Job.title }
    role_ids_data { ["system-owner"] }
  end
end
