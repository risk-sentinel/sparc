# frozen_string_literal: true

require "rails_helper"

# #860 / #842 — resolution against real records.
#
# The property under test throughout is that resolution NEVER CREATES. Every
# failing example asserts the absence of a record as well as the error, because
# "it reported an error" and "it reported an error and also provisioned the
# thing" are indistinguishable from the return value alone.
RSpec.describe IdpGrantResolver do
  subject(:resolver) { described_class.new }

  # Slugs are DERIVED from the name by Sluggable, and on create `name_changed?`
  # is true, so a slug passed to the factory is regenerated and thrown away.
  # Name the records so they slugify to what the grants address, and assert it.
  let(:organization) { create(:organization, name: "Acme") }
  let(:boundary) { create(:authorization_boundary, name: "Acme Prod", organization: organization) }

  before do
    expect(organization.slug).to eq("acme")
  end
  let!(:role) { Role.find_by(name: "isso") || create(:role, name: "isso", scope: "authorization_boundary") }

  def resolve(value) = resolver.resolve(IdpGrant.parse(value))

  describe "a boundary grant" do
    before { boundary }

    it "resolves to a user_role, naming the boundary and the Role record" do
      result = resolve("sparc:boundary:acme:acme-prod:isso")

      expect(result).to be_resolved
      expect(result.target_type).to eq(:user_role)
      expect(result.authorization_boundary).to eq(boundary)
      expect(result.role).to eq(role)
      expect(result.organization).to eq(organization)
    end

    it "resolves regardless of the case the claim was typed in" do
      result = resolve("SPARC:BOUNDARY:ACME:ACME-PROD:ISSO")

      expect(result).to be_resolved
      expect(result.authorization_boundary).to eq(boundary)
    end
  end

  describe "an org grant" do
    it "resolves to an organization_membership, which is a STRING role" do
      # Deliberately NOT a Role record: organization_memberships carries its own
      # configurable vocabulary, and org_admin there is a real permission gate.
      result = resolve("sparc:org:acme:org_admin")

      expect(result).to be_resolved
      expect(result.target_type).to eq(:organization_membership)
      expect(result.organization).to eq(organization)
      expect(result.role_name).to eq("org_admin")
      expect(result.role).to be_nil
    end

    it "refuses a role that is not in the organization's configured list" do
      result = resolve("sparc:org:acme:isso")

      expect(result).not_to be_resolved
      expect(result.error).to match(/not one of/)
    end
  end

  describe "it never creates what a grant names" do
    it "does not create a missing organization" do
      expect {
        result = resolve("sparc:org:does-not-exist:member")
        expect(result).not_to be_resolved
        expect(result.error).to match(/organization "does-not-exist" not found/)
      }.not_to change(Organization, :count)
    end

    it "does not create a missing boundary" do
      organization
      expect {
        result = resolve("sparc:boundary:acme:nope:isso")
        expect(result).not_to be_resolved
        expect(result.error).to match(/authorization boundary "nope" not found/)
      }.not_to change(AuthorizationBoundary, :count)
    end

    it "does not create a missing role" do
      boundary
      expect {
        result = resolve("sparc:boundary:acme:acme-prod:archmage")
        expect(result).not_to be_resolved
        expect(result.error).to match(/role "archmage" not found/)
      }.not_to change(Role, :count)
    end

    it "never writes a membership, even for a grant that resolves cleanly" do
      boundary
      expect {
        expect(resolve("sparc:boundary:acme:acme-prod:isso")).to be_resolved
      }.to change(UserRole, :count).by(0)

      expect { resolve("sparc:org:acme:member") }.to change(OrganizationMembership, :count).by(0)
    end
  end

  describe "the organization segment is VERIFIED, not decorative" do
    # Boundary slugs are globally unique, so the boundary would resolve on its
    # own. This is the check that stops a mis-scoped directory group granting
    # access inside a tenant nobody named.
    it "refuses a boundary owned by a different organization" do
      other = create(:organization, name: "Globex")
      globex_prod = create(:authorization_boundary, name: "Globex Prod", organization: other)
      expect(globex_prod.slug).to eq("globex-prod")

      result = resolve("sparc:boundary:acme:globex-prod:isso")

      expect(result).not_to be_resolved
      expect(result.error).to match(/does not own/)
      expect(result.error).to include("acme", "globex-prod")
    end
  end

  describe "role scope is enforced with a reason" do
    it "refuses an instance-scoped role on a boundary" do
      # UserRole validates this too, but an administrator reading the unmatched
      # queue needs the reason, not a validation error in a job log.
      boundary
      create(:role, name: "policy_manager", scope: "instance")

      result = resolve("sparc:boundary:acme:acme-prod:policy_manager")

      expect(result).not_to be_resolved
      expect(result.error).to match(/instance-scoped/)
    end
  end

  describe "an instance grant" do
    let!(:instance_role) { create(:role, name: "global_viewer", scope: "instance") }

    it "is REFUSED and reported when the instance has not opted in" do
      # Empty allowlist is the default. Refused with a reason rather than
      # dropped: someone created that directory group on purpose.
      allow(SparcConfig).to receive(:oidc_instance_roles).and_return([])

      result = resolve("sparc:instance:global_viewer")

      expect(result).not_to be_resolved
      # Pinned to THIS refusal, not merely to any mention of the variable. The
      # not-in-the-allowlist branch below also names it, so a looser assertion
      # passes with the opt-in gate deleted — measured, not assumed.
      expect(result.error).to match(/not granted from the IdP on this instance/)
    end

    it "resolves to an instance-wide user_role once opted in" do
      allow(SparcConfig).to receive(:oidc_instance_roles).and_return([ "global_viewer" ])

      result = resolve("sparc:instance:global_viewer")

      expect(result).to be_resolved
      expect(result.target_type).to eq(:user_role)
      expect(result.role).to eq(instance_role)
      # NULL boundary is what makes a user_role instance-wide.
      expect(result.authorization_boundary).to be_nil
    end

    it "refuses an instance role the operator did not name" do
      # The allowlist is per role, not a blanket switch: opting in to
      # global_viewer must not confer head_of_agency.
      create(:role, name: "head_of_agency", scope: "instance")
      allow(SparcConfig).to receive(:oidc_instance_roles).and_return([ "global_viewer" ])

      result = resolve("sparc:instance:head_of_agency")

      expect(result).not_to be_resolved
      expect(result.error).to match(/not in SPARC_OIDC_INSTANCE_ROLES/)
    end

    it "refuses a boundary-scoped role dressed up as an instance grant" do
      create(:role, name: "isso_alt", scope: "authorization_boundary")
      allow(SparcConfig).to receive(:oidc_instance_roles).and_return([ "isso_alt" ])

      result = resolve("sparc:instance:isso_alt")

      expect(result).not_to be_resolved
      expect(result.error).to match(/authorization_boundary-scoped/)
    end

    describe "the break-glass account stays unreachable" do
      it "cannot confer users.admin, because admin is not a Role" do
        # The safety property that makes instance grants acceptable at all: a
        # claim can never produce the instance-admin boolean, so recovery from
        # a misconfigured IdP is always available.
        allow(SparcConfig).to receive(:oidc_instance_roles).and_return([ "admin" ])

        result = resolve("sparc:instance:admin")

        expect(result).not_to be_resolved
        expect(result.error).to match(/not found/)
        expect(Role.exists?(name: "admin")).to be(false)
      end

      it "never produces a target other than a role membership" do
        allow(SparcConfig).to receive(:oidc_instance_roles).and_return([ "global_viewer" ])

        result = resolve("sparc:instance:global_viewer")

        expect(result.target_type).to eq(:user_role)
      end
    end
  end

  describe "a malformed grant" do
    it "carries its parse error through rather than being re-diagnosed" do
      result = resolver.resolve(IdpGrant.parse("sparc:nonsense"))

      expect(result).not_to be_resolved
      expect(result.error).to match(/unknown scope type/)
    end
  end

  describe "#resolve_all" do
    it "preserves order and reports each outcome independently" do
      boundary
      grants = IdpGrant.parse_all([
        "sparc:boundary:acme:acme-prod:isso",
        "sparc:org:acme:member",
        "sparc:boundary:acme:missing:isso"
      ])

      results = resolver.resolve_all(grants)

      expect(results.map(&:resolved?)).to eq([ true, true, false ])
    end
  end
end
