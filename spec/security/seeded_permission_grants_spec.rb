# frozen_string_literal: true

require "rails_helper"

# #919 — the fourth dimension: what the seeds actually GRANT.
#
# spec/security/permission_vocabulary_spec.rb pins defined / enforced /
# documented. All three can agree perfectly while the role catalog grants
# nothing, which is exactly the state SPARC was in: 11 keys were enforced and
# documented and granted to no role, so back-matter authoring, promotion and
# catalog/profile/CDEF approval were silently instance-admin-only.
#
# The decisions recorded in docs/dev/919_authorization_triage.md are otherwise
# enforced by nothing. A later edit to db/seeds.rb could drop the boundary tier,
# or hand `back_matter.approve_promotion` to the boundary roles and quietly
# destroy the separation of duties the promotion queue exists for, and the entire
# suite would stay green — the change is data, not behaviour.
#
# WHY THIS READS THE SEED SOURCE rather than a seeded database: the roles live in
# a `SeedRunner.run_section("roles")` block inside db/seeds.rb alongside catalog
# and demo-data sections. Loading that file to populate a test database would run
# all of them. Extracting the roles into their own file so a spec could load it
# is a refactor of shared seed infrastructure and needs its own decision, so this
# pins the source instead. The constants below ARE the policy; asserting on them
# catches the edit that would change who can do what.
#
# NIST 800-53: AC-2 (account management), AC-5 (separation of duties),
# AC-6 (least privilege), CM-6 (configuration settings).
RSpec.describe "Seeded permission grants (#919)" do
  let(:seeds) { File.read(Rails.root.join("db/seeds.rb")) }

  # Pulls a %w[...] list out of the seed source by constant name.
  def word_list(name)
    m = seeds.match(/#{name}\s*=\s*%w\[(.*?)\]/m)
    raise "#{name} not found in db/seeds.rb — was it renamed?" unless m

    m[1].split(/\s+/).reject(&:empty?).sort
  end

  # Pulls the granted keys of a permission constant, handling both forms the
  # seeds use: a `{ "key" => true }.freeze` literal, and a
  # `OTHER.merge("key" => true).freeze` derivation — where the result is the
  # base's keys plus the merged ones, so the base has to be resolved too.
  def perm_hash_keys(name)
    literal = seeds.match(/#{name}\s*=\s*\{(.*?)\}\.freeze/m)
    return scan_keys(literal[1]) if literal

    merged = seeds.match(/#{name}\s*=\s*(\w+)\.merge\((.*?)\)\.freeze/m)
    raise "#{name} not found in db/seeds.rb — was it renamed?" unless merged

    (perm_hash_keys(merged[1]) + scan_keys(merged[2])).uniq.sort
  end

  def scan_keys(fragment)
    fragment.scan(/"([a-z_]+\.[a-z_]+)"\s*=>\s*true/).flatten.sort
  end

  describe "the boundary tier" do
    # The fourteen boundary roles that already hold some document write.
    EXPECTED_BOUNDARY_ROLES = %w[
      agency_ao ao cloud_service_provider common_control_provider
      component_supplier evidence_integration_engineer issm isso
      project_member so_iso sparc_sme system_architect_engineer
      system_operator_admin vendor_dependency_manager
    ].freeze

    it "grants back-matter to exactly the fourteen decided roles" do
      expect(word_list("BACK_MATTER_BOUNDARY_ROLES")).to eq(EXPECTED_BOUNDARY_ROLES)
    end

    # Each exclusion is a distinct decision, so each gets its own example —
    # a single combined assertion would let one silently return.
    it "excludes assessor_3pao — separation of duties" do
      expect(word_list("BACK_MATTER_BOUNDARY_ROLES")).not_to include("assessor_3pao"),
        "An assessor must not edit the back-matter provenance it is assessing (AC-5)."
    end

    it "excludes view_only" do
      expect(word_list("BACK_MATTER_BOUNDARY_ROLES")).not_to include("view_only")
    end

    it "excludes the three oversight roles that write no document" do
      granted = word_list("BACK_MATTER_BOUNDARY_ROLES")

      %w[ciso information_owner_steward solution_evaluator].each do |role|
        expect(granted).not_to include(role),
          "#{role} writes no document today, so granting it back-matter authority would " \
          "give it more control over a compliance artifact than over the document that " \
          "artifact supports. The governing rule is that managing back-matter matches the " \
          "RBAC already decided for documents."
      end
    end
  end

  # The property most likely to be undone by a well-meaning edit, and the one
  # with the worst consequence: a boundary member approving their own promotion.
  describe "promotion separation of duties — the boundary requests, the instance approves" do
    it "keeps approve_promotion OFF the boundary tier" do
      expect(perm_hash_keys("PERM_BACK_MATTER_BOUNDARY")).not_to include("back_matter.approve_promotion"),
        "Promotion elevates boundary-scoped content to instance-wide authoritative. " \
        "Granting the request and the approval to the same role defeats the review queue " \
        "that exists for it (AC-5). Confirmed by the owner 2026-08-11."
    end

    it "keeps federate OFF the boundary tier" do
      expect(perm_hash_keys("PERM_BACK_MATTER_BOUNDARY")).not_to include("back_matter.federate"),
        "Federation is cross-instance, not a boundary-level act."
    end

    it "gives the boundary tier the request leg" do
      expect(perm_hash_keys("PERM_BACK_MATTER_BOUNDARY")).to include("back_matter.promote")
    end

    it "gives the instance tier both approval legs" do
      instance = perm_hash_keys("PERM_BACK_MATTER_INSTANCE")

      expect(instance).to include("back_matter.approve_promotion", "back_matter.federate")
    end
  end

  describe "the instance tier" do
    it "holds the approval keys" do
      expect(perm_hash_keys("PERM_BACK_MATTER_INSTANCE"))
        .to include("catalogs.approve", "profiles.approve", "cdef.approve")
    end

    it "is the policy team" do
      expect(word_list("BACK_MATTER_INSTANCE_ROLES")).to eq(%w[policy_manager])
    end
  end

  describe "roster management is delegable, not admin-only" do
    it "delegates to issm, isso and so_iso" do
      expect(word_list("ROSTER_MANAGER_ROLES")).to eq(%w[issm isso so_iso])
    end

    it "grants both the write and manage_members keys" do
      expect(perm_hash_keys("PERM_ROSTER_MANAGER")).to eq(
        %w[authorization_boundaries.manage_members authorization_boundaries.write]
      )
    end
  end

  describe "cdef approval spans both tiers" do
    it "includes the boundary security leads" do
      expect(word_list("CDEF_APPROVER_ROLES")).to eq(%w[issm isso so_iso])
    end
  end

  # Editing the grants without bumping the version means existing deployments
  # never receive them — the change ships and silently does nothing, which is
  # indistinguishable from it not being made.
  # #1044 — the role an IdP is told to grant must EXIST to be granted. If the
  # seeds stop defining it, IdpGrantResolver refuses the claim with "role not
  # found" and time-boxed administration silently stops working, with nothing
  # in the suite going red: the role is data, not behaviour.
  describe "the instance_admin role (#1044)" do
    it "is defined, instance-scoped, and carries admin.administer" do
      block = seeds[/\{ name: "instance_admin".*?\},/m]

      expect(block).to be_present, "the instance_admin role is no longer seeded"
      expect(block).to include('scope: "instance"'),
                       "a boundary-scoped grant confers boundary power, not instance authority"
      expect(block).to include("PERM_INSTANCE_ADMIN")
    end

    it "grants admin.administer and nothing else — the rest would be inert" do
      expect(seeds).to match(/PERM_INSTANCE_ADMIN\s*=\s*\{\s*"admin\.administer"\s*=>\s*true\s*\}/),
                       "admin.administer short-circuits has_permission?, so any other key " \
                       "listed here would imply it is doing work it is not"
    end
  end

  # 1.3.0 -> 1.4.0 for #1044, which adds the `instance_admin` role carrying
  # `admin.administer`. Without the bump SeedRunner skips the section on every
  # existing database, so the role an IdP is supposed to grant would not exist
  # to grant — the grant would resolve to "role not found" and the feature would
  # appear broken on exactly the deployments that already run SPARC.
  it "requires a seed version that reflects the seeded grants" do
    expect(SeedRunner::CURRENT_VERSIONS["roles"]).to eq("1.4.0"),
      "The roles seed version must be bumped whenever these grants change, or " \
      "SeedRunner skips the section on every existing database. If you changed the " \
      "grants above, bump the version AND update this expectation."
  end
end
