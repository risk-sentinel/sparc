require "rails_helper"

# Regression cover for the OIDC JWT decode happy path against the live
# `jwt` gem version. Closes the gap left open by api_auth_modes_spec.rb,
# which only exercises rejection paths with a fake token.
#
# Generates an in-memory RSA keypair, exposes its public key as a JWKS
# via stubbed Net::HTTP responses, signs an RS256 JWT with the private
# key, and asserts the request reaches an authenticated controller
# action. Also covers the standard rejection cases (expired, wrong
# audience, wrong issuer, wrong signing key) to prove the gem's claim
# validation is wired through the SPARC controller correctly.
#
# RSA keypair is generated once at file load to keep the suite fast.
RSpec.describe "API v1 OIDC JWT decode", type: :request do
  RSA_KEY = OpenSSL::PKey::RSA.new(2048).freeze
  KID     = "sparc-test-key-1"

  let(:issuer_url) { "https://test-idp.example.com" }
  let(:audience)   { "sparc-api-audience-id" }
  let(:jwks_url)   { "#{issuer_url}/.well-known/jwks.json" }
  let(:discovery_url) { "#{issuer_url}/.well-known/openid-configuration" }

  let(:jwk) { JWT::JWK.new(RSA_KEY, alg: "RS256", use: "sig", kid: KID) }
  let(:jwks_payload) { { keys: [ jwk.export ] } }

  let!(:user) { create(:user, email: "alice@example.com") }

  let(:valid_payload) do
    {
      iss:   issuer_url,
      aud:   audience,
      sub:   user.email,
      email: user.email,
      exp:   5.minutes.from_now.to_i,
      iat:   Time.current.to_i
    }
  end

  def encode(payload, key: RSA_KEY, kid: KID)
    JWT.encode(payload, key, "RS256", { kid: kid })
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:api_auth_mode).and_return("oidc")
    allow(SparcConfig).to receive(:oidc_issuer_url).and_return(issuer_url)
    allow(SparcConfig).to receive(:oidc_client_id).and_return(audience)

    allow(Net::HTTP).to receive(:get).with(URI(discovery_url))
                                     .and_return({ jwks_uri: jwks_url }.to_json)
    allow(Net::HTTP).to receive(:get).with(URI(jwks_url))
                                     .and_return(jwks_payload.to_json)

    Rails.cache.clear
  end

  describe "happy path" do
    it "decodes a valid RS256 JWT signed with the JWKS key and authenticates the user" do
      get api_v1_ssp_documents_path, headers: auth_headers(encode(valid_payload))
      expect(response).to have_http_status(:ok)
    end
  end

  describe "rejection paths" do
    it "rejects an expired JWT" do
      payload = valid_payload.merge(exp: 5.minutes.ago.to_i)
      get api_v1_ssp_documents_path, headers: auth_headers(encode(payload))
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a JWT with the wrong audience" do
      payload = valid_payload.merge(aud: "different-audience")
      get api_v1_ssp_documents_path, headers: auth_headers(encode(payload))
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a JWT with the wrong issuer" do
      payload = valid_payload.merge(iss: "https://evil.example.com")
      get api_v1_ssp_documents_path, headers: auth_headers(encode(payload))
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a JWT signed with a key not in the JWKS" do
      other_key = OpenSSL::PKey::RSA.new(2048)
      token = encode(valid_payload, key: other_key, kid: "evil-key")
      get api_v1_ssp_documents_path, headers: auth_headers(token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a JWT whose subject does not map to a SPARC user" do
      payload = valid_payload.merge(sub: "no-such-user@example.com",
                                    email: "no-such-user@example.com")
      get api_v1_ssp_documents_path, headers: auth_headers(encode(payload))
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("No SPARC user account found")
    end
  end
end
