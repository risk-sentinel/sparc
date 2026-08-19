FactoryBot.define do
  # #947 — an attestation is only valid if the attester actually holds an
  # attesting role on the evidence's boundary, so the factory has to build that
  # grant rather than assume it.
  #
  # The test database seeds NO roles (see docs/dev/919_authorization_triage.md),
  # which is exactly why this is built explicitly here: a factory that relied on
  # a seeded `Role` would produce records that pass because nothing was found to
  # check against, and every attestation spec would go green while asserting
  # nothing. `:unverified` exists so the failing direction can be tested too.
  factory :attestation do
    transient do
      # The boundary the grant is made on. Defaults to the evidence's own, so
      # the attester is authorized where the evidence actually lives.
      #
      # When the evidence has NO boundary it is instance-wide, and `UserRole`
      # refuses to pin a boundary-scoped role to nothing. So the grant is made
      # on a boundary of its own — which matches the rule the model applies to
      # instance-wide evidence: attest authority somewhere, since shared
      # evidence belongs to no single system.
      grant_boundary_id { evidence&.authorization_boundary_id || create(:authorization_boundary).id }
    end

    association :evidence

    attester_user do
      association(:user, strategy: :create)
    end

    role do
      attesting_role = Role.find_by(name: "attesting_role_spec", scope: "authorization_boundary") ||
        create(:role, :authorization_boundary_scoped,
               name: "attesting_role_spec",
               display_name: "Attesting Role",
               permissions: { Attestation::ATTEST_PERMISSION => true })
      attesting_role.name
    end

    statement { Faker::Lorem.paragraph(sentence_count: 3) }
    attested_at { Time.current }

    # The grant itself. Built after the attester and role exist, before
    # validation runs on save.
    after(:build) do |attestation, evaluator|
      next if attestation.attester_user.blank? || attestation.role.blank?
      # `grant_boundary_id: nil` is how a spec says "make NO grant" — it builds
      # the roster rows itself so it can control exactly what is and is not held.
      next if evaluator.grant_boundary_id.blank?

      # The role a spec named may not exist yet — the test database seeds NO
      # roles. Creating it here (with the attest permission) is establishing the
      # precondition, not weakening the check: the specs that test REJECTION
      # build their own roles and grants explicitly, and pass
      # `grant_boundary_id: nil` so this block makes no grant for them.
      granted = Role.find_by(name: attestation.role, scope: "authorization_boundary") ||
        create(:role, :authorization_boundary_scoped,
               name: attestation.role,
               display_name: attestation.role.titleize,
               permissions: { Attestation::ATTEST_PERMISSION => true })

      UserRole.find_or_create_by!(
        user_id: attestation.attester_user.id,
        role_id: granted.id,
        authorization_boundary_id: evaluator.grant_boundary_id
      )
    end

    # An attestation whose attester holds no attesting role — the state #947
    # exists to reject, and the one a "does it really check?" spec needs.
    trait :unverified do
      attester_user { nil }
      attester_name { Faker::Name.name }
      attester_email { Faker::Internet.email }

      after(:build) do |attestation|
        attestation.attester_user = nil
      end
    end

    # A legacy row as it exists on an upgraded instance: a name, no account, and
    # a role from the retired hardcoded list that maps to nothing.
    trait :legacy_control_owner do
      attester_user { nil }
      attester_name { Faker::Name.name }
      attester_email { Faker::Internet.email }
      role { "control_owner" }
    end
  end
end
