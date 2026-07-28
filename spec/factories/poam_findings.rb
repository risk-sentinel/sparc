FactoryBot.define do
  factory :poam_finding do
    poam_document
    uuid { SecureRandom.uuid }
    title { Faker::Lorem.sentence }
    description { Faker::Lorem.paragraph }
    # #840 — OSCAL requires finding/target: what was assessed and the resulting
    # state. A factory omitting it built records the model now rejects, and
    # (before #840) POA&Ms that failed schema validation only at export.
    target_data do
      {
        "type" => "statement-id",
        "target-id" => "ac-2_smt",
        "title" => "Assessment objective for AC-2",
        "status" => { "state" => "not-satisfied" }
      }
    end

    # A row as written by aggregation before #840: persisted, invalid, and
    # unsaveable until completed. Used to exercise the audit path.
    trait :targetless do
      target_data { {} }
      to_create { |instance| instance.save(validate: false) }
    end
  end
end
