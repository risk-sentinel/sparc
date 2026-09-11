# frozen_string_literal: true

require "rails_helper"

# #1044 slice 4 — an assessor must be able to tell WHICH administrative
# authority acted.
#
# After #1044 the two are indistinguishable from the outside: both pass every
# gate. They have entirely different provenance, though. The break-glass account
# is a dedicated identity whose local credential is checked out of a vault (EPV,
# AWS Secrets Manager), so attribution runs through the checkout record. A
# time-boxed instance admin is a named person the directory granted for a
# window, so attribution is the person.
#
# NIST AU-3, AU-3(1), AC-6(9).
RSpec.describe "audit attribution of administrative authority (#1044)" do
  let(:instance_admin_role) do
    Role.find_or_create_by!(name: "instance_admin") do |role|
      role.display_name = "Instance Administrator"
      role.scope        = "instance"
      role.permissions  = { "admin.administer" => true }
    end
  end

  def authority_of(user)
    AuditEvent.log(user: user, action: "login_success", provider: "local").metadata["admin_authority"]
  end

  it "records break_glass for the dedicated instance-admin account" do
    expect(authority_of(create(:user, admin: true))).to eq("break_glass")
  end

  it "records instance_admin for an IdP-granted, time-boxed administrator" do
    user = create(:user, admin: false)
    user.user_roles.create!(role: instance_admin_role, authorization_boundary: nil, source: "idp")

    expect(authority_of(user.reload)).to eq("instance_admin")
  end

  # Absent, not "none": the key marks a privileged act. Writing a value for
  # every ordinary action would bury the ones that matter.
  it "records nothing for an ordinary user" do
    expect(authority_of(create(:user, admin: false))).to be_nil
  end

  it "records nothing for an unauthenticated event" do
    expect(authority_of(nil)).to be_nil
  end

  # The two must never be confusable, which is the entire point.
  it "never labels a time-boxed administrator as break_glass" do
    user = create(:user, admin: false)
    user.user_roles.create!(role: instance_admin_role, authorization_boundary: nil, source: "idp")

    expect(authority_of(user.reload)).not_to eq("break_glass")
  end

  it "stops recording it once the grant is revoked" do
    user = create(:user, admin: false)
    grant = user.user_roles.create!(role: instance_admin_role, authorization_boundary: nil, source: "idp")
    expect(authority_of(user.reload)).to eq("instance_admin")

    grant.destroy!

    expect(authority_of(user.reload)).to be_nil
  end

  # A caller that deliberately records its own value must win — this helper adds
  # context, it does not overwrite evidence.
  it "never overwrites metadata the caller supplied" do
    event = AuditEvent.log(user: create(:user, admin: true), action: "login_success",
                           metadata: { "admin_authority" => "supplied_by_caller" })

    expect(event.metadata["admin_authority"]).to eq("supplied_by_caller")
  end
end
