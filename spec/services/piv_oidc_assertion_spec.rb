# frozen_string_literal: true

require "rails_helper"

# #822 — an OIDC token proving the IdP performed certificate-based
# authentication, as a configurable alternative to gateway-terminated mTLS.
#
# The property most of these examples defend is the refusal, not the acceptance.
# This decides whether an authentication REQUIREMENT is satisfied, so the way it
# fails matters more than the way it succeeds: an empty allowlist that accepted
# anything would silently downgrade PIV enforcement to nothing, and every
# deployment that has not opted in has exactly that empty allowlist.
RSpec.describe PivOidcAssertion do
  def auth_with(claims)
    OmniAuth::AuthHash.new(provider: "oidc", uid: "abc",
                           extra: { raw_info: claims })
  end

  describe "when nothing is configured" do
    before do
      allow(SparcConfig).to receive(:piv_oidc_acr_values).and_return([])
      allow(SparcConfig).to receive(:piv_oidc_amr_values).and_return([])
    end

    it "refuses a token that carries a smart-card claim anyway" do
      # An EMPTY allowlist means "accept nothing", never "accept anything".
      # This is the single most important property in the class: the default
      # configuration must not weaken an authentication requirement.
      assertion = described_class.new(auth_with("amr" => [ "x509", "hwk" ], "acr" => "phr"))

      expect(assertion).not_to be_satisfied
      expect(assertion.evidence).to be_nil
    end
  end

  describe "amr" do
    before do
      allow(SparcConfig).to receive(:piv_oidc_acr_values).and_return([])
      allow(SparcConfig).to receive(:piv_oidc_amr_values).and_return(%w[x509 hwk])
    end

    it "accepts a token whose amr carries an accepted method" do
      assertion = described_class.new(auth_with("amr" => [ "pwd", "x509" ]))

      expect(assertion).to be_satisfied
      expect(assertion.evidence[:amr]).to eq([ "x509" ])
    end

    it "refuses a token whose amr carries only unaccepted methods" do
      # `swk` is a SOFT key. Accepting it would be exactly the soft-cert trust
      # gap this feature exists to close.
      expect(described_class.new(auth_with("amr" => [ "pwd", "swk", "mfa" ]))).not_to be_satisfied
    end

    it "refuses a token with no amr at all" do
      expect(described_class.new(auth_with("sub" => "abc"))).not_to be_satisfied
    end

    it "matches case-insensitively, because two people type these" do
      expect(described_class.new(auth_with("amr" => [ "X509" ]))).to be_satisfied
    end

    it "tolerates a scalar amr rather than a list" do
      # The claim is specified as an array, but providers have shipped a bare
      # string; refusing a valid PIV login over that would be our bug.
      expect(described_class.new(auth_with("amr" => "x509"))).to be_satisfied
    end
  end

  describe "acr" do
    before do
      allow(SparcConfig).to receive(:piv_oidc_amr_values).and_return([])
      allow(SparcConfig).to receive(:piv_oidc_acr_values)
        .and_return([ "http://idmanagement.gov/ns/assurance/aal/3" ])
    end

    it "accepts an exact match" do
      assertion = described_class.new(
        auth_with("acr" => "http://idmanagement.gov/ns/assurance/aal/3")
      )

      expect(assertion).to be_satisfied
      expect(assertion.evidence[:acr]).to eq("http://idmanagement.gov/ns/assurance/aal/3")
    end

    it "refuses a LOWER assurance level" do
      # aal/2 is a real value an IdP will send. Substring or prefix matching
      # would accept it, which is why the comparison is exact.
      expect(
        described_class.new(auth_with("acr" => "http://idmanagement.gov/ns/assurance/aal/2"))
      ).not_to be_satisfied
    end
  end

  describe "where the claims are read from" do
    before do
      allow(SparcConfig).to receive(:piv_oidc_acr_values).and_return([])
      allow(SparcConfig).to receive(:piv_oidc_amr_values).and_return(%w[x509])
    end

    it "reads extra.raw_info, not info" do
      # OmniAuth's `info` is a normalised subset that never carries acr/amr.
      # Reading them from it would silently find nothing and refuse every PIV
      # login, with no error to explain why.
      wrong_place = OmniAuth::AuthHash.new(provider: "oidc", uid: "abc",
                                           info: { "amr" => [ "x509" ] },
                                           extra: { raw_info: {} })

      expect(described_class.new(wrong_place)).not_to be_satisfied
    end

    it "does not raise when the provider sent no raw_info" do
      bare = OmniAuth::AuthHash.new(provider: "oidc", uid: "abc")

      expect { described_class.new(bare).satisfied? }.not_to raise_error
      expect(described_class.new(bare)).not_to be_satisfied
    end
  end
end
