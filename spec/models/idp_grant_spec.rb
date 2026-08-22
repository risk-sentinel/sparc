# frozen_string_literal: true

require "rails_helper"

# #860 — parsing only. Whether the thing a grant names EXISTS is the resolver's
# question; these examples are about whether the string is well formed.
RSpec.describe IdpGrant do
  describe ".parse" do
    it "reads a boundary grant" do
      grant = described_class.parse("sparc:boundary:acme:acme-prod:reviewer")

      expect(grant).to be_valid
      expect(grant).to be_boundary_scoped
      expect(grant.organization_slug).to eq("acme")
      expect(grant.boundary_slug).to eq("acme-prod")
      expect(grant.role_name).to eq("reviewer")
    end

    it "reads an org grant" do
      grant = described_class.parse("sparc:org:acme:member")

      expect(grant).to be_valid
      expect(grant).to be_org_scoped
      expect(grant.organization_slug).to eq("acme")
      expect(grant.role_name).to eq("member")
      expect(grant.boundary_slug).to be_nil
    end

    describe "canonicalisation" do
      # Claim values are typed by hand into an IdP console. They will not match
      # the stored slug's case, and a grant that fails because someone typed
      # ACME is a support ticket, not a security control.
      it "is case-insensitive and tolerates surrounding whitespace" do
        grant = described_class.parse("  SPARC:Boundary:ACME:Acme-Prod:Reviewer  ")

        expect(grant).to be_valid
        expect(grant.organization_slug).to eq("acme")
        expect(grant.boundary_slug).to eq("acme-prod")
        expect(grant.role_name).to eq("reviewer")
      end

      it "keeps the raw value for the audit trail" do
        # What the administrator sees in the unmatched queue has to be the
        # string they typed, not our normalised version of it, or they cannot
        # find it in their own console.
        grant = described_class.parse("SPARC:Org:ACME:Member")

        expect(grant.raw).to eq("SPARC:Org:ACME:Member")
      end
    end

    describe "values that are not addressed to SPARC" do
      # A real directory claim carries every group the person is in. Returning
      # these as errors would bury the genuine failures under hundreds of lines.
      it "ignores a group without the prefix" do
        expect(described_class.parse("Everyone")).to be_nil
        expect(described_class.parse("okta-admins")).to be_nil
      end

      it "ignores blank values" do
        expect(described_class.parse("")).to be_nil
        expect(described_class.parse("   ")).to be_nil
        expect(described_class.parse(nil)).to be_nil
      end
    end

    describe "malformed values that ARE addressed to SPARC" do
      # Someone meant these for SPARC, so they are reported rather than dropped.
      it "names an unknown scope type" do
        grant = described_class.parse("sparc:tenant:acme:reviewer")

        expect(grant).not_to be_valid
        expect(grant.error).to include("tenant")
        expect(grant.error).to include("org", "boundary")
      end

      it "refuses too few segments" do
        grant = described_class.parse("sparc:boundary:acme:reviewer")

        expect(grant).not_to be_valid
        expect(grant.error).to match(/expected 4 segments/)
      end

      it "refuses too many segments" do
        grant = described_class.parse("sparc:org:acme:member:extra")

        expect(grant).not_to be_valid
        expect(grant.error).to match(/expected 3 segments/)
      end

      it "refuses an empty segment rather than resolving a blank slug" do
        grant = described_class.parse("sparc:boundary:acme::reviewer")

        expect(grant).not_to be_valid
        expect(grant.error).to match(/empty/)
      end
    end

    describe "the configurable prefix" do
      it "honours a custom prefix" do
        allow(SparcConfig).to receive(:oidc_grants_prefix).and_return("acme-sparc:")

        expect(described_class.parse("acme-sparc:org:acme:member")).to be_valid
        expect(described_class.parse("sparc:org:acme:member")).to be_nil
      end
    end
  end

  describe ".parse_all" do
    it "keeps SPARC's grants, reports SPARC's malformed ones, drops the rest" do
      values = [
        "sparc:boundary:acme:acme-prod:reviewer",
        "Everyone",                      # unrelated directory group
        "okta-admins",                   # unrelated directory group
        "sparc:org:acme:member",
        "sparc:nonsense"                 # meant for SPARC, malformed
      ]

      grants = described_class.parse_all(values)

      expect(grants.length).to eq(3)
      expect(grants.count(&:valid?)).to eq(2)
      expect(grants.reject(&:valid?).map(&:raw)).to eq([ "sparc:nonsense" ])
    end

    it "handles a missing claim without raising" do
      # Distinct from an EMPTY claim at the sync layer — here both simply parse
      # to nothing; it is the caller that must tell them apart.
      expect(described_class.parse_all(nil)).to eq([])
      expect(described_class.parse_all([])).to eq([])
    end
  end

  describe "equality" do
    it "compares on what the grant NAMES, not how it was typed" do
      a = described_class.parse("sparc:boundary:acme:acme-prod:reviewer")
      b = described_class.parse("SPARC:BOUNDARY:ACME:ACME-PROD:REVIEWER")

      expect(a).to eq(b)
      expect([ a, b ].uniq.length).to eq(1)
    end

    it "distinguishes the same role in different boundaries" do
      a = described_class.parse("sparc:boundary:acme:acme-prod:reviewer")
      b = described_class.parse("sparc:boundary:acme:acme-dev:reviewer")

      expect(a).not_to eq(b)
    end
  end
end
