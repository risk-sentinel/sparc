# frozen_string_literal: true

require "rails_helper"

# #1259 — the roles seed section applies shipped defaults one key at a time and
# never undoes an instance administrator's choice.
RSpec.describe BuiltInRoleSeeder do
  # The shipped definitions with some values changed, as a later release would
  # ship them: { "role_name" => { "key" => new_default } }.
  def shipping(changes)
    altered = BuiltInRoles.all.transform_values do |definition|
      definition.merge(permissions: definition[:permissions].dup)
    end
    changes.each do |name, values|
      values.each do |key, value|
        if BuiltInRoles::ATTRIBUTES.include?(key)
          altered[name] = altered[name].merge(key.to_sym => value)
        else
          altered[name][:permissions][key] = value
        end
      end
    end
    allow(BuiltInRoles).to receive(:all).and_return(altered)
  end

  def role(name) = Role.find_by!(name: name)

  # What the role editor and the API do with an administrator's edit.
  def admin_sets(name, key, value)
    r = role(name)
    if BuiltInRoles::ATTRIBUTES.include?(key)
      r.public_send("#{key}=", value)
    else
      r.permissions = r.permissions.merge(key => value)
    end
    r.record_admin_choices([ key ])
    r.save!
  end

  def audits(action) = AuditEvent.where(action: action)

  before { described_class.call }

  it "creates every built-in role with its shipped defaults on a fresh install" do
    expect(Role.where(name: BuiltInRoles.names).count).to eq(BuiltInRoles.names.size)
    expect(role("policy_manager").has_permission?("catalogs.write")).to be(true)
    expect(role("policy_manager").admin_overrides).to eq({})
  end

  it "never touches a role an administrator created" do
    custom = create(:role, name: "custom_reviewer", display_name: "Custom", permissions: { "ssp.write" => true })

    expect { described_class.call }.not_to(change { custom.reload.attributes })
  end

  describe "an administrator's grant" do
    before { admin_sets("view_only", "ssp.write", true) }

    it "is recorded as an override and survives a run" do
      expect(role("view_only").admin_overrides).to eq("ssp.write" => false)

      described_class.call

      expect(role("view_only").has_permission?("ssp.write")).to be(true)
    end
  end

  describe "an administrator's revoke" do
    before { admin_sets("isso", "ssp.write", false) }

    it "is recorded as an override and survives a run" do
      expect(role("isso").admin_overrides).to eq("ssp.write" => true)

      described_class.call

      expect(role("isso").has_permission?("ssp.write")).to be(false)
    end
  end

  # The pre-#1259 behaviour, shown failing: without an override record the
  # seeds DO put a changed value back. This is what proves the override is
  # what protects the grant above, not something incidental.
  it "puts a value back to the shipped default when no administrator chose it" do
    r = role("view_only")
    r.update!(permissions: r.permissions.merge("ssp.write" => true))

    described_class.call

    expect(role("view_only").has_permission?("ssp.write")).to be(false)
  end

  it "puts a display name back to the shipped default when no administrator chose it" do
    role("view_only").update!(display_name: "Renamed outside the editor")

    described_class.call

    expect(role("view_only").display_name).to eq("View Only")
  end

  it "keeps an administrator's display name, description and sort order" do
    admin_sets("view_only", "display_name", "Read-only Reviewer")
    admin_sets("view_only", "description", "Local wording.")
    admin_sets("view_only", "sort_order", 99)

    described_class.call

    expect(role("view_only")).to have_attributes(display_name: "Read-only Reviewer",
                                                 description: "Local wording.", sort_order: 99)
  end

  describe "a key new in the code" do
    before do
      stub_const("Role::PERMISSION_KEYS", Role::PERMISSION_KEYS + [ "widgets.write" ])
      shipping("view_only" => { "widgets.write" => true })
    end

    it "reaches a role the administrator never edited, and is audited" do
      described_class.call

      expect(role("view_only").has_permission?("widgets.write")).to be(true)
      event = audits("role_default_applied").find_by(subject_id: role("view_only").id)
      expect(event.metadata).to include("role_name" => "view_only", "key" => "widgets.write",
                                        "from" => false, "to" => true, "source" => "seed")
    end
  end

  describe "a changed shipped default" do
    before do
      admin_sets("isso", "ssp.write", false) # the administrator revoked it
      # The next release stops shipping poam.write to isso and so_iso.
      shipping("isso" => { "poam.write" => false }, "so_iso" => { "poam.write" => false })
    end

    it "reaches the keys nobody set, on every role, and leaves the overridden key alone" do
      described_class.call

      expect(role("isso").has_permission?("poam.write")).to be(false)
      expect(role("so_iso").has_permission?("poam.write")).to be(false)
      expect(role("isso").has_permission?("ssp.write")).to be(false)
      expect(role("so_iso").has_permission?("ssp.write")).to be(true)
    end

    it "removes a revoked default rather than storing false, as the seeds always have" do
      described_class.call

      expect(role("so_iso").permissions).not_to have_key("poam.write")
    end
  end

  describe "a shipped change an override blocks" do
    before { admin_sets("view_only", "description", "Local wording.") }

    it "keeps the administrator's value, and logs and audits the skip" do
      shipping("view_only" => { "description" => "New shipped wording." })
      allow(Rails.logger).to receive(:info).and_call_original

      result = described_class.call

      expect(role("view_only").description).to eq("Local wording.")
      expect(result.skips.map(&:key)).to eq([ "description" ])
      expect(Rails.logger).to have_received(:info).with(/role_default_skipped view_only .*description/)
      event = audits("role_default_skipped").sole
      expect(event.subject_id).to eq(role("view_only").id)
      expect(event.metadata).to include("role_name" => "view_only", "key" => "description",
                                        "value" => "Local wording.", "shipped" => "New shipped wording.",
                                        "reason" => "administrator override", "source" => "seed")
    end

    it "reports it once, not on every run" do
      shipping("view_only" => { "description" => "New shipped wording." })
      described_class.call

      expect { described_class.call }.not_to(change { audits("role_default_skipped").count })
    end

    it "keeps a revoke made against the current shipped default, and does not report it again" do
      admin_sets("view_only", "ssp.write", true)  # recorded against shipped=false
      shipping("view_only" => { "ssp.write" => true })
      described_class.call                        # agrees with the admin: nothing to skip
      admin_sets("view_only", "ssp.write", false) # now an override of shipped=true
      shipping("view_only" => { "ssp.write" => true })

      expect { described_class.call }.not_to(change { audits("role_default_skipped").count })
      expect(role("view_only").has_permission?("ssp.write")).to be(false)
    end

    it "is not reported when the new default agrees with the administrator" do
      shipping("view_only" => { "description" => "Local wording." })

      expect(described_class.call.skips).to be_empty
      expect(role("view_only").admin_overrides).to eq("description" => "Local wording.")
    end
  end

  describe "running twice" do
    it "changes nothing, and audits nothing, the second time" do
      admin_sets("isso", "ssp.write", false)
      admin_sets("view_only", "display_name", "Auditor")
      shipping("isso" => { "ssp.write" => false, "poam.write" => false },
               "view_only" => { "display_name" => "Viewer" })
      described_class.call

      snapshot = Role.order(:id).map(&:attributes)
      expect { described_class.call }.not_to(change { AuditEvent.count })
      expect(Role.order(:id).map(&:attributes)).to eq(snapshot)
    end
  end

  describe "scope" do
    before { shipping("view_only" => { "scope" => "instance" }) }

    it "is updated on a role nobody holds" do
      described_class.call

      expect(role("view_only").scope).to eq("instance")
    end

    it "is never changed on a role that has assignments, and the skip is reported" do
      create(:user_role, role: role("view_only"), authorization_boundary: create(:authorization_boundary))

      result = described_class.call

      expect(role("view_only").scope).to eq("authorization_boundary")
      expect(result.skips.map { |s| [ s.key, s.reason ] }).to include([ "scope", "role has assignments" ])
    end
  end
end
