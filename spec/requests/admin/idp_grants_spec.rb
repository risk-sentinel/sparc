# frozen_string_literal: true

require "rails_helper"

# #860 — the unmatched-grant queue on screen. A thin client over the same
# UnmatchedGrantQuery the API and the digest email read.
RSpec.describe "Admin IdP grants", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def skip_grant(user: member, grant: "sparc:boundary:acme:not-yet:isso",
                 reason: 'authorization boundary "not-yet" not found')
    AuditEvent.log(user: user, action: "idp_grant_skipped", provider: "oidc",
                   metadata: { grant: grant, reason: reason })
  end

  describe "GET /admin/idp_grants" do
    it "shows a refused grant with its reason" do
      skip_grant
      sign_in_as(admin)

      get admin_idp_grants_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("not-yet")
      expect(response.body).to include("authorization boundary")
    end

    it "says so plainly when there is nothing outstanding" do
      sign_in_as(admin)

      get admin_idp_grants_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No grants were refused")
    end

    it "explains that nothing needs clearing" do
      # The screen has to say this or an administrator will look for a button to
      # dismiss rows that resolve on their own.
      skip_grant
      sign_in_as(admin)

      get admin_idp_grants_path

      expect(response.body).to match(/resolves by itself/i)
    end

    it "honours the window parameter" do
      sign_in_as(admin)

      get admin_idp_grants_path, params: { days: 7 }

      expect(response).to have_http_status(:ok)
    end

    describe "authorization, both directions" do
      it "refuses a signed-in non-admin" do
        sign_in_as(member)

        get admin_idp_grants_path

        expect(response).not_to have_http_status(:ok)
      end

      it "refuses an anonymous visitor" do
        get admin_idp_grants_path

        expect(response).not_to have_http_status(:ok)
      end
    end
  end
end

# #860 — the queue is actionable: create what is missing, or reject a grant that
# will never be honoured.
RSpec.describe "Admin IdP grant actions", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def skip_grant(grant:, reason: "missing")
    AuditEvent.log(user: member, action: "idp_grant_skipped", provider: "oidc",
                   metadata: { grant: grant, reason: reason })
  end

  describe "the create hint" do
    it "offers to create a missing organization, and names the slug it must have" do
      # Retyping a slug out of an error message is where the mismatch creeps in:
      # the record must end up with the slug the IdP asks for, not a similar name.
      hint = UnmatchedGrantResolutionHint.new("sparc:org:acme-corp:member").hint

      expect(hint.kind).to eq(:organization)
      expect(hint.required_slug).to eq("acme-corp")
      expect(hint.suggested_name).to eq("Acme Corp")
      expect(hint.suggested_name.parameterize).to eq(hint.required_slug),
        "the suggested name does not produce the slug the grant needs"
      expect(hint.path).to start_with("/admin/organizations/new")
    end

    it "offers the boundary once its organization exists" do
      org = create(:organization, name: "Acme")

      hint = UnmatchedGrantResolutionHint.new("sparc:boundary:acme:acme-prod:isso").hint

      expect(hint.kind).to eq(:authorization_boundary)
      expect(hint.required_slug).to eq("acme-prod")
      expect(hint.path).to include("organization_id=#{org.id}")
    end

    it "offers the ORGANIZATION first when neither exists" do
      # The boundary form has nothing to attach to until the organization is
      # there, so offering it first would send an administrator to a dead end.
      hint = UnmatchedGrantResolutionHint.new("sparc:boundary:nope:nope-prod:isso").hint

      expect(hint.kind).to eq(:organization)
    end

    it "offers nothing when everything it names already exists" do
      # Then the refusal was a conflict or a scope mismatch, and "create it"
      # is the wrong advice.
      org = create(:organization, name: "Acme")
      create(:authorization_boundary, name: "Acme Prod", organization: org)
      create(:role, name: "isso", scope: "authorization_boundary")

      expect(UnmatchedGrantResolutionHint.new("sparc:boundary:acme:acme-prod:isso").hint).to be_nil
    end

    it "offers nothing for a malformed grant" do
      expect(UnmatchedGrantResolutionHint.new("sparc:nonsense").hint).to be_nil
    end
  end

  describe "POST /admin/idp_grants/dismiss" do
    it "stops reporting the grant" do
      skip_grant(grant: "sparc:org:typo:member")
      sign_in_as(admin)

      post dismiss_admin_idp_grants_path, params: { grant: "sparc:org:typo:member" }

      expect(response).to redirect_to(admin_idp_grants_path)
      # Gone from the queue itself...
      expect(UnmatchedGrantQuery.new(window: 30.days).events).to be_empty

      # ...but still visible under "Rejected grants", because a rejection an
      # administrator cannot see is one they cannot undo.
      get admin_idp_grants_path
      expect(response.body).to include("Rejected grants")
      expect(response.body).to include("sparc:org:typo:member")
      expect(response.body).to include("Restore")
    end

    it "matches however the IdP cased it" do
      # Canonical storage, or a dismissed grant reappears under a different
      # capitalisation of the same group name.
      skip_grant(grant: "SPARC:ORG:TYPO:MEMBER")
      sign_in_as(admin)

      post dismiss_admin_idp_grants_path, params: { grant: "sparc:org:typo:member" }

      expect(UnmatchedGrantQuery.new(window: 30.days).events).to be_empty
    end

    it "changes nobody's access" do
      # The grant was already refused when it arrived; dismissing only stops
      # SPARC asking about it again.
      skip_grant(grant: "sparc:org:typo:member")
      sign_in_as(admin)

      expect {
        post dismiss_admin_idp_grants_path, params: { grant: "sparc:org:typo:member" }
      }.to change(UserRole, :count).by(0)
    end

    it "records who rejected it" do
      sign_in_as(admin)

      post dismiss_admin_idp_grants_path, params: { grant: "sparc:org:typo:member", reason: "misnamed group" }

      dismissal = DismissedIdpGrant.last
      expect(dismissal.dismissed_by).to eq(admin)
      expect(dismissal.reason).to eq("misnamed group")
      expect(AuditEvent.where(action: "idp_grant_dismissed").count).to eq(1)
    end

    it "is refused for a non-admin" do
      sign_in_as(member)

      post dismiss_admin_idp_grants_path, params: { grant: "sparc:org:typo:member" }

      expect(DismissedIdpGrant.count).to eq(0)
    end
  end

  describe "DELETE /admin/idp_grants/:id/restore" do
    it "reports the grant again" do
      # Not a one-way door.
      skip_grant(grant: "sparc:org:typo:member")
      dismissal = DismissedIdpGrant.create!(grant: "sparc:org:typo:member")
      sign_in_as(admin)

      delete restore_admin_idp_grant_path(dismissal)

      expect(DismissedIdpGrant.count).to eq(0)
      expect(UnmatchedGrantQuery.new(window: 30.days).events).not_to be_empty
    end
  end

  describe "the SQL canonicalisation mirrors IdpGrant.canonicalize" do
    # UnmatchedGrantQuery filters dismissals in SQL to keep a relation, which
    # duplicates the canonical rule. This is the guard that catches the day the
    # two drift apart — without it a dismissed grant quietly reappears.
    %w[
      sparc:org:acme:member
      SPARC:ORG:ACME:MEMBER
    ].each do |raw|
      it "agrees for #{raw.inspect}" do
        DismissedIdpGrant.create!(grant: raw)
        AuditEvent.log(user: member, action: "idp_grant_skipped", provider: "oidc",
                       metadata: { grant: raw, reason: "x" })

        expect(UnmatchedGrantQuery.new(window: 30.days).events).to be_empty,
          "SQL canonicalisation and IdpGrant.canonicalize disagree on #{raw.inspect}"
      end
    end

    it "agrees when the recorded value carries surrounding whitespace" do
      DismissedIdpGrant.create!(grant: "sparc:org:acme:member")
      AuditEvent.log(user: member, action: "idp_grant_skipped", provider: "oidc",
                     metadata: { grant: "  sparc:org:acme:member  ", reason: "x" })

      expect(UnmatchedGrantQuery.new(window: 30.days).events).to be_empty
    end
  end
end
