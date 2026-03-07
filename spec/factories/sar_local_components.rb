FactoryBot.define do
  factory :sar_local_component do
    association :sar_document
    uuid { SecureRandom.uuid }
    component_type { "software" }
    title { Faker::App.name }
    description { Faker::Lorem.paragraph }
    status_state { "operational" }
  end
end
