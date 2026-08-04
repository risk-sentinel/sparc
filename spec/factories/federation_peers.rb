FactoryBot.define do
  factory :federation_peer do
    sequence(:name) { |n| "Peer #{n}" }
    sequence(:base_url) { |n| "https://peer-#{n}.example.gov" }
    enabled { true }
  end
end
