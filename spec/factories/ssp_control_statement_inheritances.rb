FactoryBot.define do
  factory :ssp_control_statement_inheritance do
    ssp_control_statement
    source factory: :cdef_control_statement
    source_uuid { SecureRandom.uuid }
    overridden { false }

    trait :from_ssp do
      source factory: :ssp_control_statement
    end

    trait :overridden do
      overridden { true }
      overridden_prose { "Locally edited prose" }
    end
  end
end
