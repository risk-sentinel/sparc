FactoryBot.define do
  factory :back_matter_resource do
    sequence(:title) { |n| "Resource #{n}" }
    description { "A supporting reference." }
    uuid { SecureRandom.uuid }
    rel { "reference" }
    source { "managed" }
    href { "https://example.gov/reference" }
  end
end
