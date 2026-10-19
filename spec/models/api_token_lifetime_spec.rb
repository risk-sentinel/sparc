# frozen_string_literal: true

require "rails_helper"

# #1176 — a service account's token must expire; any token can be renewed
# (overlapping) or reissued (at once), and neither changes its limits.
RSpec.describe ApiToken, "lifetime, renewal and reissue (#1176)" do
  let(:account) { create(:user, :service_account) }
  let(:person) { create(:user) }
  let(:admin) { create(:user, :admin) }

  def generate(user, **opts)
    described_class.generate!(user: user, name: "t", **opts)
  end

  describe "creating a service account's token" do
    it "refuses one with no expiry" do
      expect { generate(account, expires_at: nil) }
        .to raise_error(ActiveRecord::RecordInvalid, /required for a service account's token/)
    end

    it "refuses one past SPARC_API_TOKEN_MAX_DAYS, and accepts one at it" do
      allow(SparcConfig).to receive(:api_token_max_days).and_return(30)

      expect { generate(account, expires_at: 31.days.from_now) }
        .to raise_error(ActiveRecord::RecordInvalid, /at most 30 days/)
      expect(generate(account, expires_at: 30.days.from_now)).to be_persisted
    end

    it "still lets a person's token never expire (owner, 2026-10-18)" do
      expect(generate(person, expires_at: nil)).to be_persisted
    end

    it "does not cap a person's token" do
      expect(generate(person, expires_at: 3.years.from_now)).to be_persisted
    end

    it "leaves an existing never-expiring service-account token valid (no revocation on upgrade)" do
      token = generate(account, expires_at: 1.day.from_now)
      token.update_column(:expires_at, nil)

      expect(token.reload).to be_valid
      expect(token.update(name: "renamed")).to be true
      expect(described_class.authenticate(token.plaintext_token)).to eq(token)
    end
  end

  describe "endpoint limits" do
    it "refuses an entry the catalog does not know" do
      expect { generate(person, allowed_endpoints: [ "nope:read" ]) }
        .to raise_error(ActiveRecord::RecordInvalid, /not an API resource group/)
    end

    it "stores All endpoints as unrestricted" do
      expect(generate(person, allowed_endpoints: [ "*", "ssp_documents:read" ]).allowed_endpoints).to eq([])
    end
  end

  describe "#expiring_soon? and #never_expires?" do
    it "flags a live token inside the 14-day window only" do
      expect(generate(person, expires_at: 13.days.from_now)).to be_expiring_soon
      expect(generate(person, expires_at: 15.days.from_now)).not_to be_expiring_soon
      expect(generate(person, expires_at: nil)).not_to be_expiring_soon
      expect(generate(person, expires_at: nil)).to be_never_expires
    end

    it "does not call an expired token expiring soon" do
      token = generate(person, expires_at: 1.day.from_now)
      token.update_column(:expires_at, 1.minute.ago)

      expect(token).not_to be_expiring_soon
    end
  end

  describe "#renew!" do
    let!(:old) do
      generate(account, expires_at: 60.days.from_now,
               allowed_endpoints: [ "ssp_documents:read" ], allowed_cidrs: [ "10.0.0.0/8" ])
    end

    it "issues a new token with the same name, limits and lifetime" do
      replacement = old.renew!(by: admin)

      expect(replacement).to be_persisted
      expect(replacement.id).not_to eq(old.id)
      expect(replacement.plaintext_token).to start_with("sparc_sa_")
      expect(replacement.name).to eq(old.name)
      expect(replacement.allowed_endpoints).to eq([ "ssp_documents:read" ])
      expect(replacement.allowed_cidrs).to eq([ "10.0.0.0/8" ])
      expect(replacement.expires_at).to be_within(1.minute).of(60.days.from_now)
      expect(replacement.created_by).to eq(admin)
    end

    it "keeps the old token working for the grace window, and no longer" do
      allow(SparcConfig).to receive(:api_token_renewal_grace_days).and_return(7)
      old.renew!(by: admin)

      expect(old.reload.expires_at).to be_within(1.minute).of(7.days.from_now)
      expect(described_class.authenticate(old.plaintext_token)).to eq(old)
    end

    it "never extends a token that would expire sooner than the grace window" do
      old.update_column(:expires_at, 2.days.from_now)
      old.renew!(by: admin)

      expect(old.reload.expires_at).to be_within(1.minute).of(2.days.from_now)
    end

    it "ends the old token at once when the grace window is 0" do
      allow(SparcConfig).to receive(:api_token_renewal_grace_days).and_return(0)
      old.renew!(by: admin)

      expect(old.reload.expires_at).to be <= Time.current
      expect(described_class.authenticate(old.plaintext_token)).to be_nil
    end

    it "gives a never-expiring service-account token an expiry on renewal" do
      old.update_column(:expires_at, nil)

      replacement = old.renew!(by: admin)

      expect(replacement.expires_at).to be_within(1.minute).of(ApiToken::DEFAULT_SERVICE_ACCOUNT_DAYS.days.from_now)
    end

    it "keeps a person's never-expiring token never-expiring" do
      token = generate(person, expires_at: nil)

      expect(token.renew!(by: admin).expires_at).to be_nil
    end

    it "carries over a pre-#1176 path pattern even if it no longer matches a route" do
      old.update_column(:allowed_endpoints, [ "/api/v1/retired_resource*" ])

      expect(old.reload.renew!(by: admin).allowed_endpoints).to eq([ "/api/v1/retired_resource*" ])
    end

    it "clamps a carried-over lifetime longer than today's cap" do
      old.update_columns(expires_at: 500.days.from_now)
      allow(SparcConfig).to receive(:api_token_max_days).and_return(365)

      expect(old.reload.renew!(by: admin).expires_at).to be_within(1.minute).of(365.days.from_now)
    end
  end

  describe "#reissue!" do
    it "revokes the token at once and issues one with the same limits" do
      old = generate(account, expires_at: 30.days.from_now,
                     allowed_endpoints: [ "evidences:write" ], allowed_cidrs: [ "192.168.0.0/16" ])
      plaintext = old.plaintext_token

      replacement = old.reissue!(by: admin)

      expect(described_class.exists?(old.id)).to be false
      expect(described_class.authenticate(plaintext)).to be_nil
      expect(replacement.allowed_endpoints).to eq([ "evidences:write" ])
      expect(replacement.allowed_cidrs).to eq([ "192.168.0.0/16" ])
      expect(replacement.expires_at).to be_within(1.minute).of(30.days.from_now)
    end
  end

  describe ".regenerate_for!" do
    it "revokes every token and carries the newest active token's limits over" do
      generate(account, expires_at: 10.days.from_now, allowed_endpoints: [ "users:read" ])
      newest = generate(account, expires_at: 45.days.from_now,
                        allowed_endpoints: [ "ssp_documents:read" ], allowed_cidrs: [ "10.1.0.0/16" ])
      newest.update_column(:created_at, 1.minute.from_now)

      token = described_class.regenerate_for!(account, by: admin)

      expect(account.api_tokens.reload).to contain_exactly(token)
      expect(token.allowed_endpoints).to eq([ "ssp_documents:read" ])
      expect(token.allowed_cidrs).to eq([ "10.1.0.0/16" ])
      expect(token.expires_at).to be_within(2.minutes).of(45.days.from_now)
    end

    it "uses limits given explicitly, including an explicit empty list" do
      generate(account, expires_at: 10.days.from_now, allowed_endpoints: [ "users:read" ])

      token = described_class.regenerate_for!(account, by: admin, expires_in_days: 20,
                                              allowed_endpoints: [], allowed_cidrs: [])

      expect(token.allowed_endpoints).to eq([])
      expect(token.expires_at).to be_within(1.minute).of(20.days.from_now)
    end

    it "refuses an explicit lifetime past the cap rather than shortening it, and revokes nothing" do
      kept = generate(account, expires_at: 10.days.from_now)
      allow(SparcConfig).to receive(:api_token_max_days).and_return(30)

      expect { described_class.regenerate_for!(account, by: admin, expires_in_days: 60) }
        .to raise_error(ActiveRecord::RecordInvalid, /at most 30 days/)
      expect(described_class.exists?(kept.id)).to be true
    end

    it "refuses an explicit 0 (never) for a service account" do
      expect { described_class.regenerate_for!(account, by: admin, expires_in_days: 0) }
        .to raise_error(ActiveRecord::RecordInvalid, /required/)
    end

    it "gives an account with no tokens the default lifetime and no limits" do
      token = described_class.regenerate_for!(account, by: admin)

      expect(token.expires_at).to be_within(1.minute).of(ApiToken::DEFAULT_SERVICE_ACCOUNT_DAYS.days.from_now)
      expect(token.allowed_endpoints).to eq([])
    end
  end
end
