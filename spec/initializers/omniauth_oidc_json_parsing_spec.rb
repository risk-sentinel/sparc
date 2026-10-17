# frozen_string_literal: true

require "rails_helper"

# OIDC sign-in talks to the IdP through openid_connect / swd / rack-oauth2, and
# every one of them parses the IdP's answers with Faraday's JSON response
# middleware. In v1.17.0 that middleware (faraday 2.14.3) called
# `JSON.parse(body, {})`, which json 3 rejects, so discovery raised and no one
# could sign in with Okta. The OmniAuth request specs mock the strategy and
# never parse a real IdP response, which is how it shipped.
#
# These examples replace only the network hop (Faraday's adapter) and keep each
# gem's own middleware stack, so an IdP's `application/json` answer goes through
# exactly the parsing a deployment does.
RSpec.describe "OIDC IdP responses through the OIDC gems' HTTP stack" do
  let(:issuer) { "https://idp.example.test/oauth2/default" }
  let(:signing_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:discovery_document) do
    {
      issuer: issuer,
      authorization_endpoint: "#{issuer}/v1/authorize",
      token_endpoint: "#{issuer}/v1/token",
      userinfo_endpoint: "#{issuer}/v1/userinfo",
      jwks_uri: "#{issuer}/v1/keys",
      response_types_supported: %w[code],
      subject_types_supported: %w[public],
      id_token_signing_alg_values_supported: %w[RS256]
    }
  end
  let(:id_token) do
    JSON::JWT.new(iss: issuer, sub: "00u-okta-user", aud: "sparc-client",
                  iat: Time.now.to_i, exp: Time.now.to_i + 300).sign(signing_key, :RS256).to_s
  end
  let(:idp_responses) do
    {
      "/oauth2/default/.well-known/openid-configuration" => discovery_document,
      "/oauth2/default/v1/keys" => { keys: [ JSON::JWK.new(signing_key.public_key).as_json ] },
      "/oauth2/default/v1/token" => { access_token: "at-123", token_type: "Bearer",
                                      expires_in: 3600, id_token: id_token }
    }
  end
  let(:idp_adapter) do
    responses = idp_responses
    Class.new(Faraday::Adapter) do
      define_method(:call) do |env|
        super(env)
        body = responses.fetch(env.url.path) { raise "unexpected IdP request: #{env.method} #{env.url}" }
        save_response(env, 200, body.to_json, { "Content-Type" => "application/json; charset=utf-8" })
        @app.call(env)
      end
    end
  end

  before { allow(Faraday).to receive(:default_adapter).and_return(idp_adapter) }

  it "discovers the provider configuration (swd)" do
    config = OpenIDConnect::Discovery::Provider::Config.discover!(issuer)

    expect(config.authorization_endpoint).to eq("#{issuer}/v1/authorize")
    expect(config.token_endpoint).to eq("#{issuer}/v1/token")
  end

  it "fetches the signing keys (openid_connect)" do
    jwks = OpenIDConnect::Discovery::Provider::Config.discover!(issuer).jwks

    expect(jwks.first.to_key.to_pem).to eq(signing_key.public_key.to_pem)
  end

  it "exchanges the authorization code for tokens and verifies the id_token (rack-oauth2)" do
    client = OpenIDConnect::Client.new(identifier: "sparc-client", secret: "test-secret", # gitleaks:allow
                                       redirect_uri: "https://sparc.example.test/auth/oidc/callback",
                                       token_endpoint: "#{issuer}/v1/token")
    client.authorization_code = "code-from-idp"

    token = client.access_token!
    decoded = OpenIDConnect::ResponseObject::IdToken.decode(token.id_token, signing_key.public_key)

    expect(token.access_token).to eq("at-123")
    expect { decoded.verify!(issuer: issuer, client_id: "sparc-client") }.not_to raise_error
    expect(decoded.sub).to eq("00u-okta-user")
  end
end
