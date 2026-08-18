FactoryBot.define do
  # #947 — evidence now has two completeness rules, so the default factory has
  # to satisfy both or every spec that merely needs "some evidence" would fail
  # on rules it is not testing:
  #
  #   * at least one control link (evidence supporting nothing cannot be
  #     assessed), and
  #   * a file for artefact types / an attestation for attestation types.
  #
  # The traits below exist so the FAILING directions can still be built
  # deliberately — a factory that could only produce valid records would make
  # the validations untestable.
  factory :evidence do
    title { Faker::Lorem.sentence(word_count: 3) }
    evidence_type { "artifact" }
    status { "draft" }
    description { Faker::Lorem.paragraph }
    collected_by { Faker::Name.name }
    collected_at { Time.current }
    source { Faker::Internet.url }

    transient do
      # Set to false to build evidence with NO control links — the state the
      # 1:n rule rejects.
      with_control_link { true }
      # A SEQUENCE, not a fixed id. A constant default collides with any spec
      # that links the same control explicitly (uniqueness is scoped per
      # evidence), and `zz-` is visibly a fixture rather than a real control a
      # spec might also be asserting on.
      sequence(:control_id) { |n| "zz-#{n}" }
      # Set to false to build artefact-type evidence with no file — the state
      # the file rule rejects.
      with_file { true }
    end

    after(:build) do |evidence, evaluator|
      if evaluator.with_control_link && evidence.evidence_control_links.none?
        evidence.evidence_control_links.build(control_id: evaluator.control_id)
      end

      # Attestation types are satisfied by their statement, not a file, so one
      # is not attached for them.
      next unless evaluator.with_file
      next if evidence.attestation_type?
      next if evidence.file.attached?

      evidence.file.attach(
        io: StringIO.new("SPARC spec fixture"),
        filename: "evidence.txt",
        content_type: "text/plain"
      )
    end

    trait :with_authorization_boundary do
      association :authorization_boundary
    end

    # #947 — an attestation IS evidence: the statement is the substance and no
    # file is required. Builds the assertion alongside the record, the way the
    # form does.
    trait :attestation do
      evidence_type { "signed_statement" }

      after(:build) do |evidence|
        next if evidence.attestations.any?

        evidence.attestations.build(
          attributes_for(:attestation).except(:evidence)
        )
      end
    end

    # The states the new rules reject, for testing that they do.
    trait :without_control_links do
      with_control_link { false }
    end

    trait :without_file do
      with_file { false }
    end

    trait :collected do
      status { "collected" }
    end

    trait :attested do
      status { "attested" }
    end

    trait :scan_result do
      evidence_type { "scan_result" }
    end

    trait :policy_document do
      evidence_type { "policy_document" }
    end
  end
end
