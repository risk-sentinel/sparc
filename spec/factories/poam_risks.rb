FactoryBot.define do
  factory :poam_risk do
    poam_document
    uuid { SecureRandom.uuid }
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    # #832 — statement and deadline are required. `statement` is OSCAL-required
    # substantive content; `deadline` is the SPARC rule that a POA&M item must
    # carry a time commitment. A factory omitting them built records the model
    # now rejects — and, before #832, POA&Ms that failed schema validation only
    # at export.
    statement { Faker::Lorem.paragraph }
    deadline { 90.days.from_now }
    status { %w[open investigating remediating deviation-requested deviation-approved closed].sample }
    likelihood { %w[high medium low].sample }
    impact { %w[high medium low].sample }

    # A row as it exists in a database written before #832: persisted, invalid,
    # and unsaveable until completed. Used to exercise the audit path.
    trait :incomplete do
      statement { nil }
      deadline { nil }
      to_create { |instance| instance.save(validate: false) }
    end
  end
end
