# frozen_string_literal: true

require "rails_helper"

# #1082 — "enable" and "require" were separate axes an operator had to get right
# independently, and nothing validated the pair. Requiring a method that was not
# enabled produced an instance that demanded a sign-in method it did not offer.
RSpec.describe "SparcConfig enable-vs-require (#1082)" do
  def with_env(vars)
    original = vars.keys.index_with { |k| ENV.fetch(k, nil) }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe "a requirement routes enablement" do
    it "enables PIV when PIV is required and SPARC_ENABLE_PIV was never set" do
      with_env("SPARC_REQUIRE_AUTH_METHODS" => "piv", "SPARC_ENABLE_PIV" => nil) do
        expect(SparcConfig.enable_piv?).to be(true)
      end
    end

    it "enables local login when local is required" do
      with_env("SPARC_REQUIRE_AUTH_METHODS" => "local", "SPARC_ENABLE_LOCAL_LOGIN" => nil) do
        expect(SparcConfig.enable_local_login?).to be(true)
      end
    end

    it "honours the fido2 alias — requiring 'fido2' enables webauthn" do
      with_env("SPARC_REQUIRE_AUTH_METHODS" => "fido2", "SPARC_FIDO2_ENABLED" => nil,
               "SPARC_REQUIRE_FIDO2" => nil) do
        expect(SparcConfig.fido2_enabled?).to be(true)
      end
    end

    it "leaves an unrelated method alone" do
      with_env("SPARC_REQUIRE_AUTH_METHODS" => "piv", "SPARC_ENABLE_LDAP" => nil) do
        expect(SparcConfig.enable_ldap?).to be(false)
      end
    end

    # The #785 precedent: an inference can only turn something ON that the
    # operator already asked for. An explicit "false" is a decision and wins.
    it "an explicit SPARC_ENABLE_*=false still wins over the requirement" do
      with_env("SPARC_REQUIRE_AUTH_METHODS" => "piv", "SPARC_ENABLE_PIV" => "false") do
        expect(SparcConfig.enable_piv?).to be(false)
      end
    end
  end

  describe "usable vs enabled" do
    it "reports oidc as NOT usable when it is required but has no client id" do
      with_env("SPARC_REQUIRE_AUTH_METHODS" => "oidc", "SPARC_OIDC_CLIENT_ID" => nil,
               "SPARC_ENABLE_OIDC" => nil) do
        expect(SparcConfig.auth_method_usable?("oidc")).to be(false)
        expect(SparcConfig.unusable_required_auth_methods).to eq([ "oidc" ])
      end
    end

    it "reports ldap as NOT usable without a host, even when enabled" do
      with_env("SPARC_ENABLE_LDAP" => "true", "SPARC_LDAP_HOST" => nil) do
        expect(SparcConfig.enable_ldap?).to be(true)
        expect(SparcConfig.auth_method_usable?("ldap")).to be(false)
      end
    end

    it "splits a mixed policy into usable and unusable" do
      with_env("SPARC_REQUIRE_AUTH_METHODS" => "piv,oidc", "SPARC_ENABLE_PIV" => nil,
               "SPARC_OIDC_CLIENT_ID" => nil, "SPARC_ENABLE_OIDC" => nil) do
        expect(SparcConfig.usable_required_auth_methods).to eq([ "piv" ])
        expect(SparcConfig.unusable_required_auth_methods).to eq([ "oidc" ])
      end
    end
  end

  describe "what the login page may offer" do
    it "offers everything usable when no policy is set" do
      with_env("SPARC_REQUIRE_AUTH_METHODS" => nil, "SPARC_ENABLE_LOCAL_LOGIN" => "true") do
        expect(SparcConfig.offer_auth_method?("local")).to be(true)
      end
    end

    # The bug: local login rendered, accepted a password, and the session was
    # ended on the next request — which reads as SPARC signing you out at random.
    it "does NOT offer a usable method the gate would refuse" do
      with_env("SPARC_REQUIRE_AUTH_METHODS" => "piv", "SPARC_ENABLE_LOCAL_LOGIN" => "true",
               "SPARC_ENABLE_PIV" => nil) do
        expect(SparcConfig.auth_method_usable?("local")).to be(true)
        expect(SparcConfig.offer_auth_method?("local")).to be(false)
      end
    end

    it "offers a required method through its alias — 'sso' permits oidc" do
      with_env("SPARC_REQUIRE_AUTH_METHODS" => "sso", "SPARC_OIDC_CLIENT_ID" => "abc123",
               "SPARC_ENABLE_OIDC" => nil) do
        expect(SparcConfig.offer_auth_method?("oidc")).to be(true)
      end
    end

    it "never offers a method that is not usable, policy or no policy" do
      with_env("SPARC_REQUIRE_AUTH_METHODS" => "oidc", "SPARC_OIDC_CLIENT_ID" => nil,
               "SPARC_ENABLE_OIDC" => nil) do
        expect(SparcConfig.offer_auth_method?("oidc")).to be(false)
      end
    end
  end

  # The page asks with an operator token ("oidc"); the #805 gate asks with a
  # provider ("openid_connect"). One table, or they drift and the page offers
  # what the gate refuses — which is the whole bug.
  describe "the shared alias table" do
    it "resolves the same token set from either end" do
      expect(SparcConfig.auth_method_tokens("openid_connect"))
        .to eq(SparcConfig.auth_method_tokens("oidc"))
    end

    it "returns the bare token for methods that have no aliases" do
      expect(SparcConfig.auth_method_tokens("local")).to eq([ "local" ])
    end
  end
end
