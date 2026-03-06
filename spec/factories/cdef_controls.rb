FactoryBot.define do
  factory :cdef_control do
    control_id { "SV-#{Faker::Number.number(digits: 6)}r1_rule" }
    title { Faker::Lorem.sentence }
    severity { %w[high medium low info].sample }
    cdef_document
  end
end
