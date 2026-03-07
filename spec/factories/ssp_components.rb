FactoryBot.define do
  factory :ssp_component do
    ssp_document
    uuid { SecureRandom.uuid }
    component_type { "software" }
    title { Faker::App.name }
    description { Faker::Lorem.sentence }
    status_state { "operational" }

    trait :this_system do
      component_type { "this-system" }
      title { "This System" }
      description { "The system described by this SSP." }
    end
  end
end
