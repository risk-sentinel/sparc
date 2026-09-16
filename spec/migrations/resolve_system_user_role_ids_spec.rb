# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260916180000_resolve_system_user_role_ids.rb")

# #1134 — the `role-ids` `import_boundary_users` left dangling.
#
# Every example asserts the same invariant from the other end: afterwards, every
# id in `system-implementation.users[].role-ids` resolves to a role the document
# declares.
RSpec.describe ResolveSystemUserRoleIds do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  around do |example|
    DeferredDataMigration.executing!
    example.run
  ensure
    DeferredDataMigration.idle!
  end

  let(:document) { create(:ssp_document) }

  def user(ids, doc = document) = create(:ssp_user, ssp_document: doc, role_ids_data: ids)

  def ids_on(record) = record.reload.role_ids_data

  def declared(doc = document) = doc.reload.declared_role_ids

  def declared_role(id, doc = document) = doc.reload.declared_roles.find { |r| r["id"] == id }

  def expect_every_reference_to_resolve(doc = document)
    doc.reload
    expect(doc.ssp_users.flat_map(&:role_ids_data)).to all(be_in(doc.declared_role_ids))
  end

  describe "route 1: an id that already resolves" do
    it "is left alone, and metadata.roles is not authored" do
      u = user([ "system-owner" ])

      migration.resolve_system_user_role_ids

      expect(ids_on(u)).to eq([ "system-owner" ])
      expect(document.reload.metadata_extra.to_h).not_to have_key("roles")
    end

    # An uploaded document may declare its own `isso`. Its declaration wins over
    # the membership table — remapping it would change what the document says.
    it "wins over the membership mapping when the document declares that exact id" do
      document.update!(metadata_extra: { "roles" => [ { "id" => "isso", "title" => "Our ISSO" } ] })
      u = user([ "isso" ])

      migration.resolve_system_user_role_ids

      expect(ids_on(u)).to eq([ "isso" ])
      expect(declared).to eq([ "isso" ])
    end
  end

  describe "route 2: what the import wrote" do
    it "maps a membership role NIST names onto NIST's id without declaring anything new" do
      u = user([ "authorizing_official" ])

      migration.resolve_system_user_role_ids

      expect(ids_on(u)).to eq([ "authorizing-official" ])
      expect(document.reload.metadata_extra.to_h).not_to have_key("roles")
      expect_every_reference_to_resolve
    end

    # The route the form-normaliser alone would get wrong: `isso` normalises to
    # `isso`, and only the membership table knows NIST's id for it.
    it "maps isso onto information-system-security-officer" do
      u = user([ "isso" ])

      migration.resolve_system_user_role_ids

      expect(ids_on(u)).to eq([ "information-system-security-officer" ])
      expect_every_reference_to_resolve
    end

    it "declares a membership role NIST does not name as organization-defined" do
      u = user([ "view_only" ])

      migration.resolve_system_user_role_ids

      expect(ids_on(u)).to eq([ "view-only" ])
      expect(OscalRole.organization_defined?(declared_role("view-only"))).to be(true)
      expect(declared).to include(*OscalRole::SSP_DEFAULT_IDS)
      expect_every_reference_to_resolve
    end

    it "agrees with what a fresh import would produce" do
      migrated = user([ "ciso" ])
      fresh = create(:ssp_document)
      fresh_ids = fresh.declare_membership_roles([ "ciso" ])

      migration.resolve_system_user_role_ids

      expect(ids_on(migrated)).to eq([ fresh_ids["ciso"] ])
      expect(declared_role("ciso")).to eq(fresh.declared_roles.find { |r| r["id"] == "ciso" })
    end
  end

  describe "route 3: a form variant" do
    it "rewrites onto a declared role" do
      u = user([ "System Owner" ])

      migration.resolve_system_user_role_ids

      expect(ids_on(u)).to eq([ "system-owner" ])
    end

    it "declares a NIST-suggested role with NIST's id, not as organization-defined" do
      u = user([ "Asset Owner" ])

      migration.resolve_system_user_role_ids

      expect(ids_on(u)).to eq([ "asset-owner" ])
      expect(OscalRole.organization_defined?(declared_role("asset-owner"))).to be(false)
      expect_every_reference_to_resolve
    end
  end

  describe "route 4: nothing recognises it" do
    it "declares it organization-defined, keeping the typed phrase as the title" do
      u = user([ "Policy Department" ])

      migration.resolve_system_user_role_ids

      expect(ids_on(u)).to eq([ "policy-department" ])
      role = declared_role("policy-department")
      expect(role["title"]).to eq("Policy Department")
      expect(OscalRole.organization_defined?(role)).to be(true)
    end

    it "declares a role two users share exactly once" do
      user([ "Policy Department" ])
      user([ "policy_department" ])

      migration.resolve_system_user_role_ids

      expect(declared.count("policy-department")).to eq(1)
      expect_every_reference_to_resolve
    end
  end

  it "removes a value carrying no id and keeps its neighbours" do
    u = user([ "---", "system-owner" ])

    migration.resolve_system_user_role_ids

    expect(ids_on(u)).to eq([ "system-owner" ])
  end

  it "does not resurrect defaults a document deliberately removed" do
    document.update!(metadata_extra: { "roles" => [] })
    user([ "system_owner" ])

    migration.resolve_system_user_role_ids

    expect(declared).to eq([ "system-owner" ])
  end

  describe "idempotency and resume-from-partial" do
    it "is a no-op on a second run" do
      u = user([ "isso", "ciso", "Policy Department" ])

      migration.resolve_system_user_role_ids
      after_first = [ ids_on(u), document.reload.metadata_extra ]

      migration.resolve_system_user_role_ids

      expect([ ids_on(u), document.reload.metadata_extra ]).to eq(after_first)
    end

    it "resolves the users a halted run had not reached yet" do
      first  = user([ "view_only" ])
      second = user([ "view_only" ])
      # Simulate a run that got through `first` and died before `second`.
      first.update_columns(role_ids_data: [ "view-only" ])
      document.update!(metadata_extra: { "roles" => document.declared_roles +
        [ OscalRole.from_membership_role("view_only") ] })

      migration.resolve_system_user_role_ids

      expect(ids_on(first)).to eq([ "view-only" ])
      expect(ids_on(second)).to eq([ "view-only" ])
      expect(declared.count("view-only")).to eq(1)
    end

    it "leaves a resolved document alone and still processes its neighbour" do
      done = create(:ssp_document)
      done_user = user([ "system-owner" ], done)
      pending = user([ "system_owner" ])

      migration.resolve_system_user_role_ids

      expect(ids_on(done_user)).to eq([ "system-owner" ])
      expect(done.reload.metadata_extra.to_h).not_to have_key("roles")
      expect(ids_on(pending)).to eq([ "system-owner" ])
    end
  end
end
