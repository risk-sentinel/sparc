# frozen_string_literal: true

require "rails_helper"

# GHSA-m27g-v28p-f9fx — an OAuth provider (GitHub, GitLab) sends the IdP a
# callback URL that OmniAuth builds from the request's Host, X-Forwarded-Host
# or Forwarded header, which a client can forge. SPARC pins it to
# SPARC_APP_URL (SparcConfig.oauth_full_host, set in
# config/initializers/omniauth.rb) whenever that is set.
#
# NIST 800-53: IA-8, SC-23.
RSpec.describe "OAuth callback host" do
  describe "SparcConfig.oauth_full_host" do
    def with_app_url(value)
      original = ENV.fetch("SPARC_APP_URL", nil)
      value.nil? ? ENV.delete("SPARC_APP_URL") : ENV["SPARC_APP_URL"] = value
      yield
    ensure
      original.nil? ? ENV.delete("SPARC_APP_URL") : ENV["SPARC_APP_URL"] = original
    end

    it "is SPARC_APP_URL's origin" do
      with_app_url("https://sparc.example.gov/some/path") do
        expect(SparcConfig.oauth_full_host).to eq("https://sparc.example.gov")
      end
    end

    it "keeps a non-default port" do
      with_app_url("https://localhost:3443") do
        expect(SparcConfig.oauth_full_host).to eq("https://localhost:3443")
      end
    end

    it "is nil, not localhost, when SPARC_APP_URL is unset, blank or not a URL" do
      [ nil, "", "not a url", "sparc.example.gov" ].each do |value|
        with_app_url(value) { expect(SparcConfig.oauth_full_host).to be_nil, value.inspect }
      end
    end
  end

  describe "the callback URL a GitHub sign-in sends" do
    let(:forged) { "attacker.example" }

    def callback_url_for(env_overrides)
      strategy = OmniAuth::Strategies::GitHub.new(->(_env) { [ 200, {}, [] ] }, "id", "secret")
      env = Rack::MockRequest.env_for("https://sparc.example.gov/auth/github", method: "POST")
                             .merge(env_overrides)
      strategy.instance_variable_set(:@env, env)
      strategy.callback_url
    end

    around do |example|
      original = OmniAuth.config.full_host
      example.run
    ensure
      OmniAuth.config.full_host = original
    end

    it "follows a forged Host header when no host is pinned (the gap this closes)" do
      OmniAuth.config.full_host = nil

      expect(callback_url_for("HTTP_HOST" => forged)).to start_with("https://#{forged}/")
    end

    it "ignores forged Host and X-Forwarded-Host headers once SPARC's host is pinned" do
      OmniAuth.config.full_host = "https://sparc.example.gov"

      url = callback_url_for("HTTP_HOST" => forged, "HTTP_X_FORWARDED_HOST" => forged)
      expect(url).to eq("https://sparc.example.gov/auth/github/callback")
    end
  end
end
