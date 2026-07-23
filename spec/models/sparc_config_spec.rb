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

    # #785 — raised 50 → 100 so the prod task definition need not set it.
    # The variable remains a supported override.
    it "defaults max_upload_mb to 100" do
      ENV.delete("SPARC_MAX_UPLOAD_MB")
      expect(SparcConfig.max_upload_mb).to eq(100)
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

  describe "environment/rules header (#682)" do
    around do |ex|
      saved = %w[SPARC_HEADER_TEXT SPARC_HEADER_TEXT_COLOR SPARC_HEADER_HIGHLIGHT_COLOR]
              .index_with { |k| ENV[k] }
      ex.run
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    describe ".header_text / .header_enabled?" do
      it "is disabled by default (no SPARC_HEADER_TEXT)" do
        ENV.delete("SPARC_HEADER_TEXT")
        expect(SparcConfig.header_enabled?).to be(false)
        expect(SparcConfig.header_text).to eq("")
      end

      it "is disabled when the text is blank/whitespace-only" do
        ENV["SPARC_HEADER_TEXT"] = "   "
        expect(SparcConfig.header_enabled?).to be(false)
      end

      it "is enabled and returns the text verbatim, including special characters" do
        ENV["SPARC_HEADER_TEXT"] = %q(PRODUCTION — Authorized use only «PII» & <ok> ☣)
        expect(SparcConfig.header_enabled?).to be(true)
        expect(SparcConfig.header_text).to eq(%q(PRODUCTION — Authorized use only «PII» & <ok> ☣))
      end
    end

    describe ".header_text_color / .header_highlight_color" do
      it "defaults to the WCAG-AA brand pair when unset" do
        ENV.delete("SPARC_HEADER_TEXT_COLOR")
        ENV.delete("SPARC_HEADER_HIGHLIGHT_COLOR")
        expect(SparcConfig.header_text_color).to eq("#ffffff")
        expect(SparcConfig.header_highlight_color).to eq("#1f6fa5")
      end

      it "accepts valid hex (#rgb, #rrggbb, #rrggbbaa) and rgb()/rgba()" do
        { "#fff" => "#fff",
          "#0B1F2A" => "#0B1F2A",
          "#1f6fa5cc" => "#1f6fa5cc",
          "rgb(31, 111, 165)" => "rgb(31, 111, 165)",
          "rgba(0,0,0,0.5)" => "rgba(0,0,0,0.5)" }.each do |input, expected|
          ENV["SPARC_HEADER_TEXT_COLOR"] = input
          expect(SparcConfig.header_text_color).to eq(expected)
        end
      end

      it "falls back to the default on a malformed / injection-y value" do
        [ "red", "#12", "#1234567", "blue; content:url(x)", "</div><script>",
          "rgb(1,2)", "expression(alert(1))", "" ].each do |bad|
          ENV["SPARC_HEADER_HIGHLIGHT_COLOR"] = bad
          expect(SparcConfig.header_highlight_color).to eq("#1f6fa5")
        end
      end
    end

    describe ".environments (#770)" do
      after { ENV.delete("SPARC_ENVIRONMENTS_LIST") }

      it "defaults to the six standard environments with codes" do
        ENV.delete("SPARC_ENVIRONMENTS_LIST")
        names = SparcConfig.environments.map { |e| e[:name] }
        codes = SparcConfig.environments.map { |e| e[:code] }
        expect(names).to eq([ "Development", "Test", "Staging",
                             "User Acceptance Testing", "Quality Assurance", "Production" ])
        expect(codes).to eq(%w[DEV TEST STAG UAT QA PROD])
      end

      it "slugs the name into the stored value, round-tripping legacy values" do
        expect(SparcConfig.environment_values).to include(
          "development", "test", "staging", "production", "user_acceptance_testing"
        )
      end

      it "parses a custom Name:CODE list from the env var" do
        ENV["SPARC_ENVIRONMENTS_LIST"] = "Sandbox:SBX, Production:PROD"
        expect(SparcConfig.environments).to eq([
          { name: "Sandbox", code: "SBX", value: "sandbox" },
          { name: "Production", code: "PROD", value: "production" }
        ])
      end

      it "defaults a missing code to the name" do
        ENV["SPARC_ENVIRONMENTS_LIST"] = "Lab"
        expect(SparcConfig.environments.first).to eq({ name: "Lab", code: "Lab", value: "lab" })
      end

      it "labels a value as 'Name (CODE)', falling back to a titleized slug" do
        expect(SparcConfig.environment_label("quality_assurance")).to eq("Quality Assurance (QA)")
        expect(SparcConfig.environment_label("legacy_value")).to eq("Legacy Value")
      end
    end
  end
end
