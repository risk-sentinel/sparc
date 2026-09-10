# frozen_string_literal: true

require "rails_helper"

# #1082 — the boot check that turns a request-time lockout into a start-up
# failure. `config/initializers/zz_auth_posture.rb` is the caller; the decision
# is here so it can be tested.
RSpec.describe AuthPosture do
  def policy(required:, usable:)
    allow(SparcConfig).to receive_messages(
      require_auth_methods?: required.any?,
      required_auth_methods: required,
      usable_required_auth_methods: usable,
      unusable_required_auth_methods: required - usable
    )
  end

  describe ".lockout?" do
    it "is true when a policy is set and NOTHING it requires is usable" do
      policy(required: [ "oidc", "piv" ], usable: [])

      expect(described_class).to be_lockout
    end

    # The gate is an OR: one working method is enough to sign in with, so
    # refusing to boot here would turn a typo in a secondary method into the
    # very outage this check exists to prevent.
    it "is FALSE when at least one required method is usable" do
      policy(required: [ "oidc", "piv" ], usable: [ "piv" ])

      expect(described_class).not_to be_lockout
    end

    it "is false when no policy is set at all" do
      policy(required: [], usable: [])

      expect(described_class).not_to be_lockout
    end
  end

  describe ".partial?" do
    it "is true when some required methods work and some do not" do
      policy(required: [ "oidc", "piv" ], usable: [ "piv" ])

      expect(described_class).to be_partial
    end

    it "is false when everything required works" do
      policy(required: [ "piv" ], usable: [ "piv" ])

      expect(described_class).not_to be_partial
    end

    it "is false in a full lockout — that is the other, louder case" do
      policy(required: [ "oidc" ], usable: [])

      expect(described_class).not_to be_partial
    end
  end

  describe "the lockout message" do
    # An operator reading "oidc is not usable" should not have to work out
    # which variable supplies it.
    it "names the missing credential variable, not just the method" do
      policy(required: [ "oidc" ], usable: [])

      expect(described_class.lockout_message).to include("SPARC_OIDC_CLIENT_ID")
    end

    it "names SPARC_LDAP_HOST for an unusable ldap requirement" do
      policy(required: [ "ldap" ], usable: [])

      expect(described_class.lockout_message).to include("SPARC_LDAP_HOST")
    end

    it "says which accounts survive it, so recovery is not a guess" do
      policy(required: [ "oidc" ], usable: [])

      # \s+ because the heredoc wraps the phrase across two lines.
      expect(described_class.lockout_message).to match(/break-glass\s+bootstrap admin/i)
    end

    # piv needs no credential — a requirement alone enables it — so there is no
    # variable to name and the message must not invent one.
    it "adds no credential line for a switch-style method" do
      policy(required: [ "piv" ], usable: [])

      expect(described_class.lockout_message).not_to match(/piv\s+also needs/)
    end
  end

  describe "the partial message" do
    it "distinguishes the unusable method from the ones that still work" do
      policy(required: [ "oidc", "piv" ], usable: [ "piv" ])

      expect(described_class.partial_message).to include("oidc")
      expect(described_class.partial_message).to match(/not a lockout/i)
    end
  end
end
