FactoryBot.define do
  factory :ssp_by_component do
    ssp_control
    ssp_component
    uuid { SecureRandom.uuid }
    implementation_status { "planned" }
  end
end
