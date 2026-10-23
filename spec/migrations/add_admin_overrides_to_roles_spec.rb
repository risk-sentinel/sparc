# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261022170000_add_admin_overrides_to_roles.rb")

# #1259 — the upgrade cannot tell an administrator's past edit from the default
# it replaced, so it records every current difference from what roles section
# 1.4.0 applied as the administrator's choice, and audits each one.
RSpec.describe AddAdminOverridesToRoles do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  after { Role.reset_column_information }

  let(:baseline) do
    JSON.parse(described_class::BASELINE.read).index_by { |entry| entry["name"] }
  end

  # A built-in role exactly as roles section 1.4.0 left it: the granted keys
  # only, which is all the old seeds ever wrote.
  def seed_as_before(name)
    entry = baseline.fetch(name)
    Role.create!(entry.slice("name", "display_name", "scope", "sort_order", "description")
                      .merge("permissions" => entry["permissions"].index_with(true)))
  end

  # Keys this release adds. An install being upgraded never had them, so no
  # editor before #1259 could have written them.
  def keys_added_by_this_release = %w[cdef.scope_instance]

  # What the role editor and API wrote before #1259: every key that existed
  # then, true or false.
  def editor_save(role, changes = {})
    keys = Role::PERMISSION_KEYS - keys_added_by_this_release
    full = keys.to_h { |key| [ key, role.permissions[key] == true ] }.merge(changes)
    role.update_columns(permissions: full)
  end

  it "adds the column to a database that predates it" do
    ActiveRecord::Base.connection.remove_column(:roles, :admin_overrides)
    Role.reset_column_information

    migration.up

    expect(ActiveRecord::Base.connection.column_exists?(:roles, :admin_overrides, :jsonb)).to be(true)
  end

  it "records nothing for a role still at the defaults it was seeded with" do
    seed_as_before("isso")

    migration.up

    expect(Role.find_by!(name: "isso").admin_overrides).to eq({})
    expect(AuditEvent.where(action: "role_override_recorded")).to be_empty
  end

  it "records nothing for a role an administrator saved without changing" do
    editor_save(seed_as_before("isso"))

    migration.up

    expect(Role.find_by!(name: "isso").admin_overrides).to eq({})
  end

  it "records every difference as an override, with the default it replaced, and audits each" do
    isso = seed_as_before("isso")
    editor_save(isso, "ssp.write" => false, "amendment.approve" => true)
    isso.update_columns(display_name: "System Security Officer")

    migration.up

    expect(isso.reload.admin_overrides).to eq("ssp.write" => true, "amendment.approve" => false,
                                              "display_name" => "ISSO")
    events = AuditEvent.where(action: "role_override_recorded", subject_id: isso.id)
    expect(events.map { |e| e.metadata["key"] }).to contain_exactly("ssp.write", "amendment.approve", "display_name")
    expect(events.find { |e| e.metadata["key"] == "ssp.write" }.metadata)
      .to include("role_name" => "isso", "value" => false, "shipped" => true, "source" => "upgrade")
  end

  it "keeps an explicitly saved value for a key whose shipped default has since changed" do
    allow(BuiltInRoles).to receive(:default_for).and_call_original
    allow(BuiltInRoles).to receive(:default_for).with("view_only", "ssp.write").and_return(true)
    saved = seed_as_before("view_only")
    editor_save(saved)                    # wrote "ssp.write" => false explicitly
    untouched = seed_as_before("isso")    # isso's ssp.write default did not move

    migration.up

    expect(saved.reload.admin_overrides).to eq("ssp.write" => false)
    expect(untouched.reload.admin_overrides).to eq({})
  end

  it "does not treat an absent key as a choice when its default has changed" do
    allow(BuiltInRoles).to receive(:default_for).and_call_original
    allow(BuiltInRoles).to receive(:default_for).with("view_only", "ssp.write").and_return(true)
    role = seed_as_before("view_only")

    migration.up

    expect(role.reload.admin_overrides).to eq({})
  end

  it "leaves a role an administrator created alone" do
    custom = create(:role, name: "custom_reviewer", display_name: "Custom", permissions: { "ssp.write" => true })

    migration.up

    expect(custom.reload.admin_overrides).to eq({})
  end

  it "is a no-op the second time, and audits nothing new" do
    editor_save(seed_as_before("isso"), "ssp.write" => false)
    migration.up

    expect { migration.up }.not_to(change { AuditEvent.count })
    expect(Role.find_by!(name: "isso").admin_overrides).to eq("ssp.write" => true)
  end

  it "resumes: a role recorded by an earlier, interrupted run is not recorded twice" do
    isso = seed_as_before("isso")
    editor_save(isso, "ssp.write" => false)
    isso.update_columns(admin_overrides: { "ssp.write" => true })
    editor_save(seed_as_before("view_only"), "ssp.write" => true)

    migration.up

    expect(AuditEvent.where(action: "role_override_recorded").map { |e| e.metadata["role_name"] }).to eq([ "view_only" ])
  end

  # #1257 ships Policy Manager's cdef.write as a default change on top of the
  # 1.4.0 snapshot. These run the real shipped defaults, no stubs: the upgrade,
  # then the roles section.
  describe "Policy Manager's cdef.write on an existing install (#1257)" do
    def upgrade
      migration.up
      BuiltInRoleSeeder.call
      Role.find_by!(name: "policy_manager")
    end

    it "reaches a Policy Manager role nobody edited, and is audited" do
      seed_as_before("policy_manager")

      role = upgrade
      expect(role.has_permission?("cdef.write")).to be(true)
      expect(role.has_permission?("cdef.scope_instance")).to be(true)
      events = AuditEvent.where(action: "role_default_applied").map(&:metadata)
      expect(events.map { |m| m.slice("role_name", "key", "to") }).to contain_exactly(
        { "role_name" => "policy_manager", "key" => "cdef.write", "to" => true },
        { "role_name" => "policy_manager", "key" => "cdef.scope_instance", "to" => true }
      )
    end


    it "reaches a Policy Manager role an administrator edited elsewhere" do
      pm = seed_as_before("policy_manager")
      pm.update_columns(permissions: pm.permissions.merge("ssp.write" => true)) # granted, cdef.write untouched

      role = upgrade

      expect(role.has_permission?("cdef.write")).to be(true)
      expect(role.has_permission?("ssp.write")).to be(true)
    end

    it "keeps an administrator's revoke, and reports the skipped grant" do
      editor_save(seed_as_before("policy_manager")) # the editor wrote cdef.write => false

      expect(upgrade.has_permission?("cdef.write")).to be(false)
      skip_event = AuditEvent.where(action: "role_default_skipped").sole
      expect(skip_event.metadata).to include("role_name" => "policy_manager", "key" => "cdef.write",
                                             "value" => false, "shipped" => true)
    end

    it "keeps an administrator's earlier grant without reporting a skip" do
      editor_save(seed_as_before("policy_manager"), "cdef.write" => true)

      expect(upgrade.has_permission?("cdef.write")).to be(true)
      expect(AuditEvent.where(action: "role_default_skipped")).to be_empty
    end
  end

  it "then lets the roles seed section keep every recorded choice" do
    isso = seed_as_before("isso")
    editor_save(isso, "ssp.write" => false)
    migration.up

    BuiltInRoleSeeder.call

    expect(isso.reload.has_permission?("ssp.write")).to be(false)
  end
end
