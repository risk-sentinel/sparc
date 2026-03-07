FactoryBot.define do
  factory :poam_local_component do
    poam_document
    uuid { SecureRandom.uuid }
    component_type { "software" }
    title { Faker::App.name }
    description { Faker::Lorem.paragraph }
  end
end
