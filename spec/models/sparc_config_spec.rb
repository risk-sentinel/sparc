require "rails_helper"

RSpec.describe SparcConfig do
  describe ".VERSION" do
    it "returns a version string" do
      expect(SparcConfig::VERSION).to be_a(String)
      expect(SparcConfig::VERSION).to match(/\d+\.\d+\.\d+/)
    end
  end

  describe ".any_auth_enabled?" do
    it "returns a boolean" do
      expect(SparcConfig.any_auth_enabled?).to be_in([ true, false ])
    end
  end

  describe ".app_name" do
    it "returns a string" do
      expect(SparcConfig.app_name).to be_a(String)
    end
  end

  describe "upload limit accessors (#510)" do
    around do |ex|
      old_mb = ENV["SPARC_MAX_UPLOAD_MB"]
      old_av = ENV["SPARC_MAX_AVATAR_MB"]
      ex.run
      ENV["SPARC_MAX_UPLOAD_MB"] = old_mb
      ENV["SPARC_MAX_AVATAR_MB"] = old_av
    end

    it "defaults max_upload_mb to 50" do
      ENV.delete("SPARC_MAX_UPLOAD_MB")
      expect(SparcConfig.max_upload_mb).to eq(50)
    end

    it "converts max_upload_mb to bytes via 1.megabyte" do
      ENV["SPARC_MAX_UPLOAD_MB"] = "10"
      expect(SparcConfig.max_upload_bytes).to eq(10 * 1.megabyte)
    end

    it "defaults max_avatar_mb to 2" do
      ENV.delete("SPARC_MAX_AVATAR_MB")
      expect(SparcConfig.max_avatar_mb).to eq(2)
    end

    it "converts max_avatar_mb to bytes" do
      ENV["SPARC_MAX_AVATAR_MB"] = "5"
      expect(SparcConfig.max_avatar_bytes).to eq(5 * 1.megabyte)
    end
  end

  describe ".xlsx_uploads_enabled? (#510)" do
    around do |ex|
      old = ENV["SPARC_ENABLE_XLSX_UPLOADS"]
      ex.run
      ENV["SPARC_ENABLE_XLSX_UPLOADS"] = old
    end

    it "defaults to false" do
      ENV.delete("SPARC_ENABLE_XLSX_UPLOADS")
      expect(SparcConfig.xlsx_uploads_enabled?).to be false
    end

    it "is true only when env var equals the literal string 'true'" do
      ENV["SPARC_ENABLE_XLSX_UPLOADS"] = "true"
      expect(SparcConfig.xlsx_uploads_enabled?).to be true
    end

    it "is false for any non-'true' value" do
      ENV["SPARC_ENABLE_XLSX_UPLOADS"] = "1"
      expect(SparcConfig.xlsx_uploads_enabled?).to be false
    end
  end

  describe ".oauth_origin" do
    it "strips the path, query, and fragment to leave scheme://host" do
      expect(SparcConfig.oauth_origin("https://acme.okta.com/oauth2/default")).to eq("https://acme.okta.com")
    end

    it "preserves a non-default port" do
      expect(SparcConfig.oauth_origin("https://idp.example.com:8443/oidc")).to eq("https://idp.example.com:8443")
    end

    it "omits the default https port" do
      expect(SparcConfig.oauth_origin("https://idp.example.com:443/oidc")).to eq("https://idp.example.com")
    end

    it "returns nil for blank input" do
      expect(SparcConfig.oauth_origin(nil)).to be_nil
      expect(SparcConfig.oauth_origin("")).to be_nil
    end

    it "returns nil for a value with no scheme/host" do
      expect(SparcConfig.oauth_origin("not a url")).to be_nil
    end
  end

  describe ".oauth_form_action_origins" do
    # Save/restore every env var this reads so specs don't leak into each other.
    around do |ex|
      keys = %w[SPARC_GITHUB_CLIENT_ID SPARC_GITLAB_CLIENT_ID SPARC_GITLAB_SITE
                SPARC_ENABLE_OIDC SPARC_OIDC_ISSUER_URL]
      saved = keys.to_h { |k| [ k, ENV[k] ] }
      keys.each { |k| ENV.delete(k) }
      ex.run
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    it "is empty when no SSO provider is enabled" do
      expect(SparcConfig.oauth_form_action_origins).to eq([])
    end

    it "includes github.com when GitHub OAuth is enabled" do
      ENV["SPARC_GITHUB_CLIENT_ID"] = "gh-client"
      expect(SparcConfig.oauth_form_action_origins).to eq([ "https://github.com" ])
    end

    it "includes the configured GitLab site origin when GitLab is enabled" do
      ENV["SPARC_GITLAB_CLIENT_ID"] = "gl-client"
      ENV["SPARC_GITLAB_SITE"]      = "https://gitlab.example.com/"
      expect(SparcConfig.oauth_form_action_origins).to eq([ "https://gitlab.example.com" ])
    end

    it "includes the OIDC issuer origin (host only) when OIDC is enabled" do
      ENV["SPARC_ENABLE_OIDC"]     = "true"
      ENV["SPARC_OIDC_ISSUER_URL"] = "https://acme.okta.com/oauth2/default"
      expect(SparcConfig.oauth_form_action_origins).to eq([ "https://acme.okta.com" ])
    end

    it "omits OIDC when enabled but the issuer URL is blank" do
      ENV["SPARC_ENABLE_OIDC"] = "true"
      expect(SparcConfig.oauth_form_action_origins).to eq([])
    end

    it "combines all enabled providers" do
      ENV["SPARC_GITHUB_CLIENT_ID"] = "gh"
      ENV["SPARC_ENABLE_OIDC"]      = "true"
      ENV["SPARC_OIDC_ISSUER_URL"]  = "https://acme.okta.com/oauth2/default"
      expect(SparcConfig.oauth_form_action_origins)
        .to contain_exactly("https://github.com", "https://acme.okta.com")
    end
  end
end
