# frozen_string_literal: true

require "rails_helper"

# #1098 — an OIDC sign-in that cannot reach the identity provider says so.
#
# OmniAuth's on_failure hook calls OmniauthCallbacksController#failure
# directly, with the exception in env["omniauth.error"] and no `message`
# parameter, so every such failure read "Authentication failed: Unknown error".
# These drive the action with the env OmniAuth sets.
RSpec.describe "OIDC sign-in when the identity provider is unreachable (#1098)", type: :request do
  let(:issuer) { "https://idp.example.gov/oauth2/default" }
  let(:reference) { "req-1098-invented-0001" }

  before do
    allow(SparcConfig).to receive(:oidc_issuer_url).and_return(issuer)
  end

  def fail_with(error, type: error&.message&.to_sym, message: nil)
    params = { strategy: "oidc" }
    params[:message] = message if message
    get "/auth/failure", params: params, headers: { "X-Request-Id" => reference },
                         env: { "omniauth.error" => error, "omniauth.error.type" => type }
  end

  def with_env(vars)
    saved = vars.keys.index_with { ENV[_1] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  def without_proxy_env(&)
    with_env(%w[HTTPS_PROXY https_proxy HTTP_PROXY http_proxy NO_PROXY no_proxy].index_with(nil), &)
  end

  describe "the sign-in page" do
    it "says a discovery failure could not reach the IdP, with a reference, and no internals" do
      without_proxy_env { fail_with(OpenIDConnect::Discovery::DiscoveryFailed.new("Connection reset by peer - SSL_connect")) }

      expect(response).to redirect_to(login_path)
      expect(flash[:error]).to include("could not reach the identity provider")
      expect(flash[:error]).to include("network egress (proxy)")
      expect(flash[:error]).to include("Reference: #{reference}")
      expect(flash[:error]).not_to include("SSL_connect")
      expect(flash[:error]).not_to include("Unknown error")
    end

    {
      "a connection failure" => Faraday::ConnectionFailed.new("Failed to open TCP connection"),
      "a TLS failure" => OpenSSL::SSL::SSLError.new("certificate verify failed"),
      "a refused connection" => Errno::ECONNREFUSED.new
    }.each do |name, error|
      it "treats #{name} the same way" do
        without_proxy_env { fail_with(error) }
        expect(flash[:error]).to include("could not reach the identity provider")
      end
    end

    it "treats the strategy's timeout and failed-to-connect types the same way" do
      %i[timeout failed_to_connect].each do |type|
        without_proxy_env { fail_with(nil, type: type) }
        expect(flash[:error]).to include("could not reach the identity provider"), type.to_s
      end
    end

    it "keeps a credential failure's message" do
      fail_with(OmniAuth::Strategies::OAuth2::CallbackError.new(:invalid_grant, "bad code"),
                type: :invalid_credentials, message: "invalid_credentials")

      expect(flash[:error]).to eq("Authentication failed: Invalid credentials")
    end

    it "keeps an unclassified failure as it was" do
      fail_with(RuntimeError.new("something else"))
      expect(flash[:error]).to eq("Authentication failed: Unknown error")
    end
  end

  it "records login_failure exactly as before" do
    expect {
      without_proxy_env { fail_with(OpenIDConnect::Discovery::DiscoveryFailed.new("reset")) }
    }.to change { AuditEvent.where(action: "login_failure").count }.by(1)

    event = AuditEvent.where(action: "login_failure").order(:id).last
    expect(event.provider).to eq("oidc")
    expect(event.metadata).to eq("error" => "Unknown error")
  end

  describe "the log" do
    before { allow(Rails.logger).to receive(:error).and_call_original }

    it "names the exception, and hints at HTTPS_PROXY when no proxy applies to the issuer" do
      allow(Rails.logger).to receive(:warn).and_call_original
      without_proxy_env { fail_with(OpenIDConnect::Discovery::DiscoveryFailed.new("Connection reset by peer")) }

      expect(Rails.logger).to have_received(:error)
        .with(a_string_including("OpenIDConnect::Discovery::DiscoveryFailed: Connection reset by peer"))
      expect(Rails.logger).to have_received(:warn).with(a_string_including("no HTTPS_PROXY applies to the issuer"))
    end

    it "gives no proxy hint when a proxy applies, and never logs the proxy URL" do
      allow(Rails.logger).to receive(:warn).and_call_original
      proxy = "http://user:secret@egress.example.gov:8080"
      without_proxy_env do
        with_env("HTTPS_PROXY" => proxy) { fail_with(OpenIDConnect::Discovery::DiscoveryFailed.new("reset")) }
      end

      expect(Rails.logger).not_to have_received(:warn).with(a_string_including("HTTPS_PROXY"))
      expect(Rails.logger).not_to have_received(:error).with(a_string_including("secret"))
    end
  end

  describe SparcHttp, ".proxied?" do
    it "follows the scheme-strict, NO_PROXY-aware rule outbound calls use" do
      without_proxy_env do
        expect(described_class.proxied?(issuer)).to be(false)
        with_env("HTTP_PROXY" => "http://egress.example.gov:8080") { expect(described_class.proxied?(issuer)).to be(false) }
        with_env("HTTPS_PROXY" => "http://egress.example.gov:8080") do
          expect(described_class.proxied?(issuer)).to be(true)
          with_env("NO_PROXY" => "idp.example.gov") { expect(described_class.proxied?(issuer)).to be(false) }
        end
        expect(described_class.proxied?("not a url")).to be(false)
      end
    end
  end

  describe OidcEgressPosture, ".line" do
    before { allow(SparcConfig).to receive(:enable_oidc?).and_return(true) }

    it "names the issuer host and whether a proxy applies, never the proxy URL" do
      without_proxy_env do
        expect(described_class.line).to include("issuer host idp.example.gov; no egress proxy applies")
        with_env("HTTPS_PROXY" => "http://user:secret@egress.example.gov:8080") do
          expect(described_class.line).to include("an egress proxy applies (HTTPS_PROXY)")
          expect(described_class.line).not_to include("secret")
          expect(described_class.line).not_to include("egress.example.gov")
        end
      end
    end

    it "still reports, without a host, when the issuer URL does not parse" do
      allow(SparcConfig).to receive(:oidc_issuer_url).and_return("https://idp example.gov/oauth2")
      without_proxy_env { expect(described_class.line).to include("issuer host (unparseable issuer URL); no egress proxy applies") }
    end

    it "says nothing when OIDC sign-in is off" do
      allow(SparcConfig).to receive(:enable_oidc?).and_return(false)
      expect(described_class.line).to be_nil
    end
  end
end
