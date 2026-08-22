# frozen_string_literal: true

require "rails_helper"

# #860 / #842 — the sync, and above all the things it refuses to do.
#
# Most of these examples are about NOT changing something. That is deliberate:
# the epic exists because the naive implementation of this feature silently
# de-provisions a customer, and a suite that only proves the happy path would
# pass against exactly that implementation.
RSpec.describe EntitlementSync do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, name: "Acme") }
  let(:boundary) { create(:authorization_boundary, name: "Acme Prod", organization: organization) }
  let!(:isso) { Role.find_by(name: "isso") || create(:role, name: "isso", scope: "authorization_boundary") }

  def sync(values, mode: "authoritative", present: true)
    described_class.new(user: user, claim_values: values, claim_present: present, mode: mode)
  end

  describe "mode off" do
    it "changes nothing, whatever the claim says" do
      boundary
      plan = sync([ "sparc:boundary:acme:acme-prod:isso" ], mode: "off").apply

      expect(plan.changes).to be_empty
      expect(user.user_roles.count).to eq(0)
    end
  end

  describe "a MISSING claim versus an EMPTY one" do
    # The distinction the whole epic turns on. A typo'd claim name must not read
    # as "this user has no entitlements".
    it "errors and syncs nothing when the claim was absent" do
      user.user_roles.create!(role: isso, authorization_boundary: boundary, source: "idp")

      plan = sync([], present: false).apply

      expect(plan).to be_error
      expect(plan.error).to match(/was not present in the token/)
      expect(plan.changes).to be_empty
      expect(user.user_roles.reload.count).to eq(1), "an absent claim revoked a membership"
    end

    it "treats an EMPTY claim as a legitimate 'no grants' and revokes" do
      user.user_roles.create!(role: isso, authorization_boundary: boundary, source: "idp")

      plan = sync([], present: true).apply

      expect(plan).not_to be_error
      expect(plan.revoke.size).to eq(1)
      expect(user.user_roles.reload.count).to eq(0)
    end
  end

  describe "dry run" do
    it "reports the diff and writes nothing" do
      boundary
      plan = sync([ "sparc:boundary:acme:acme-prod:isso" ]).dry_run

      expect(plan.add.size).to eq(1)
      expect(plan.summary).to match(/1 to add/)
      expect(plan.changes.none?(&:applied)).to be(true)
      expect(user.user_roles.count).to eq(0)
    end

    it "computes the SAME plan the apply would carry out" do
      # One code path, so a preview cannot disagree with the run.
      boundary
      previewed = sync([ "sparc:boundary:acme:acme-prod:isso" ]).dry_run
      applied   = sync([ "sparc:boundary:acme:acme-prod:isso" ]).apply

      expect(applied.changes.map(&:action)).to eq(previewed.changes.map(&:action))
      expect(applied.applied_count).to eq(1)
    end
  end

  describe "bootstrap mode" do
    it "adds but never revokes" do
      user.user_roles.create!(role: isso, authorization_boundary: boundary, source: "idp")
      other = create(:role, name: "issm", scope: "authorization_boundary")

      plan = sync([ "sparc:boundary:acme:acme-prod:issm" ], mode: "bootstrap").apply

      expect(plan.add.size).to eq(1)
      expect(plan.revoke).to be_empty
      expect(user.user_roles.reload.pluck(:role_id)).to contain_exactly(isso.id, other.id)
    end
  end

  describe "revocation is scoped to what the sync created" do
    it "NEVER revokes a membership an administrator granted" do
      # The guarantee the design rests on. Even in authoritative mode, with an
      # empty claim, a manual grant survives.
      user.user_roles.create!(role: isso, authorization_boundary: boundary, source: "manual")

      plan = sync([], present: true).apply

      expect(plan.revoke).to be_empty
      expect(user.user_roles.reload.count).to eq(1)
    end

    it "does not take ownership of a manual row the IdP also grants" do
      # If the sync re-sourced it to "idp", a directory that never granted it
      # could revoke it later.
      manual = user.user_roles.create!(role: isso, authorization_boundary: boundary, source: "manual")

      plan = sync([ "sparc:boundary:acme:acme-prod:isso" ]).apply

      expect(plan.unchanged.size).to eq(1)
      expect(manual.reload.source).to eq("manual")
    end
  end

  describe "organization memberships, which are unique per (org, user)" do
    # The org role vocabulary is operator-configured via SPARC_ORGANIZATION_ROLES
    # and is often DISPLAY LABELS ("Member"), not keys ("member") — this repo's
    # own .env does exactly that. Resolve it rather than hardcoding, or the spec
    # passes locally and fails wherever the variable differs.
    let(:member_role) do
      OrganizationMembership.available_roles.find { |r| IdpGrant.canonicalize(r) == "member" }
    end

    it "bridges a claim to a configured role LABEL, not just a key" do
      # The property that makes label-configured vocabularies work at all: the
      # grant is canonicalised and so is the configured entry.
      skip "this instance has no 'member' org role configured" if member_role.nil?
      # Lazy let: name it here, or it is built AFTER the resolve and the
      # organization genuinely does not exist yet.
      organization

      resolution = IdpGrantResolver.new.resolve(IdpGrant.parse("sparc:org:acme:member"))

      expect(resolution).to be_resolved
      expect(resolution.role_name).to eq(member_role)
    end

    it "refuses to overwrite a role an administrator set, and says so" do
      skip "this instance has no 'member' org role configured" if member_role.nil?
      user.organization_memberships.create!(organization: organization, role: member_role, source: "manual")

      plan = sync([ "sparc:org:acme:org_admin" ]).apply

      expect(plan.conflicts.size).to eq(1)
      expect(plan.conflicts.first.reason).to match(/an administrator set/)
      expect(user.organization_memberships.reload.first.role).to eq(member_role)
    end

    it "updates a role it set itself" do
      skip "this instance has no 'member' org role configured" if member_role.nil?
      user.organization_memberships.create!(organization: organization, role: member_role, source: "idp")

      plan = sync([ "sparc:org:acme:org_admin" ]).apply

      expect(plan.update.size).to eq(1)
      expect(user.organization_memberships.reload.first.role).to eq("org_admin")
    end
  end

  describe "the blast-radius guard" do
    it "refuses a plan that would revoke more than the configured share" do
      allow(SparcConfig).to receive(:oidc_sync_max_revoke_pct).and_return(25)
      %w[isso issm ciso].each do |name|
        role = Role.find_by(name: name) || create(:role, name: name, scope: "authorization_boundary")
        user.user_roles.create!(role: role, authorization_boundary: boundary, source: "idp")
      end

      plan = sync([], present: true).apply

      expect(plan).to be_blocked
      expect(plan.blocked_reason).to match(/over the 25% limit/)
      expect(user.user_roles.reload.count).to eq(3), "a blocked plan still revoked"
    end

    it "allows a plan inside the limit" do
      allow(SparcConfig).to receive(:oidc_sync_max_revoke_pct).and_return(50)
      isso_row = user.user_roles.create!(role: isso, authorization_boundary: boundary, source: "idp")
      issm = create(:role, name: "issm", scope: "authorization_boundary")
      user.user_roles.create!(role: issm, authorization_boundary: boundary, source: "idp")

      plan = sync([ "sparc:boundary:acme:acme-prod:issm" ]).apply

      expect(plan).not_to be_blocked
      expect(user.user_roles.reload.pluck(:id)).not_to include(isso_row.id)
    end
  end

  describe "unmatched grants" do
    it "reports them with a reason and applies the rest" do
      boundary
      plan = sync([
        "sparc:boundary:acme:acme-prod:isso",
        "sparc:boundary:acme:missing-boundary:isso"
      ], mode: "bootstrap").apply

      expect(plan.add.size).to eq(1)
      expect(plan.unmatched.size).to eq(1)
      expect(plan.unmatched.first.error).to match(/not found/)
      expect(user.user_roles.reload.count).to eq(1)
    end
  end

  describe "a user whose grants name nothing SPARC has yet" do
    # Owner, 2026-08-22: "the user we can create but if they contain a grant we
    # don't know about (Organization / Boundary) they could log in but only see
    # things that are behind the auth required".
    #
    # That is the intended shape and it is worth pinning, because the tempting
    # alternatives are both wrong: creating the organization would let the IdP
    # mint tenants, and refusing the login would turn an estate that has not
    # caught up yet into an outage for a legitimately authenticated person.
    it "is provisioned with NO memberships, and the grants are reported" do
      plan = sync([
        "sparc:org:not-created-yet:member",
        "sparc:boundary:not-created-yet:nor-this:isso"
      ]).apply

      expect(plan.unmatched.size).to eq(2)
      expect(plan.changes).to be_empty

      # No boundary and no organization membership, so nothing boundary-scoped
      # is reachable. The account exists and can authenticate; it simply sees
      # only what any signed-in user sees.
      expect(user.user_roles.reload).to be_empty
      expect(user.organization_memberships.reload).to be_empty
      expect(user).to be_active
    end

    it "grants the part that DOES resolve and reports the rest" do
      # A partial estate is the normal case during onboarding, not an error.
      boundary
      plan = sync([
        "sparc:boundary:acme:acme-prod:isso",
        "sparc:boundary:acme:not-created-yet:isso"
      ]).apply

      expect(plan.add.size).to eq(1)
      expect(plan.unmatched.size).to eq(1)
      expect(user.user_roles.reload.count).to eq(1)
    end

    it "heals on the next login once the estate catches up" do
      # No administrator action beyond creating the boundary: the grant is
      # re-evaluated every sign-in, which is why the unmatched queue is a view
      # over recent refusals rather than a task list someone must clear.
      first = sync([ "sparc:boundary:acme:acme-prod:isso" ]).apply
      expect(first.unmatched.size).to eq(1)

      boundary # the administrator creates it

      second = sync([ "sparc:boundary:acme:acme-prod:isso" ]).apply
      expect(second.unmatched).to be_empty
      expect(second.add.size).to eq(1)
      expect(user.user_roles.reload.count).to eq(1)
    end
  end

  describe "an unknown mode" do
    it "errors rather than guessing" do
      plan = sync([], mode: "aggressive").apply

      expect(plan).to be_error
      expect(plan.error).to match(/unknown sync mode/)
    end
  end
end
