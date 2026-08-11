# frozen_string_literal: true

require "rails_helper"
require "tempfile"

# #867 — the consent banner is the AC-8 / PL-4 / PS-6 artifact stating THIS
# deployment's rules of behavior, but its text could only come from a file baked
# into the image. Changing a sentence meant rebuild → re-sign → release → image
# bump, which is the wrong owner for a per-deployment legal notice.
#
# SPARC_BANNER_HTML supplies the body inline. The properties that matter:
# inline content is sanitized exactly as file content is, the file path keeps
# working untouched, and precedence is loud rather than silent.
RSpec.describe "Inline consent banner (#867)", type: :request do
  # Reach the real methods; each example sets only the ENV it cares about.
  def with_env(**vars)
    # ENV keys are Strings; kwargs arrive as Symbols.
    original = vars.keys.index_with { |k| ENV.fetch(k.to_s, nil) }
    vars.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
  end

  describe "inline content" do
    it "renders the banner from SPARC_BANNER_HTML with no file involved" do
      with_env(SPARC_BANNER_HTML: "<p>Inline rules of behavior.</p>") do
        get login_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("consentBannerLabel")
        expect(response.body).to include("Inline rules of behavior.")
      end
    end

    it "turns the banner on by presence alone, like the file path does (#785)" do
      with_env(SPARC_BANNER_HTML: "<p>On by inference.</p>") do
        expect(SparcConfig.banner_enabled?).to be(true)
      end
    end

    it "ignores SPARC_BANNER_ENABLED=false — the content is the switch (#867)" do
      with_env(SPARC_BANNER_HTML: "<p>Still shown.</p>", SPARC_BANNER_ENABLED: "false") do
        expect(SparcConfig.banner_enabled?).to be(true)

        get login_path
        expect(response.body).to include("Still shown.")
      end
    end
  end

  # #867 — SPARC_BANNER_ENABLED is retired. It could never turn the banner ON
  # (content does that), and its old `raw == "true"` parsing was case-sensitive
  # AND short-circuited the inference, so =TRUE alongside good content silently
  # DISABLED an AC-8 notice. Every value is now ignored, and the failure
  # direction is safe: a stale flag can only leave the notice showing.
  describe "SPARC_BANNER_ENABLED is retired" do
    %w[true TRUE 1 yes on false FALSE 0 no off maybe].each do |value|
      it "ignores #{value.inspect} and follows the content instead" do
        with_env(SPARC_BANNER_HTML: "<p>Notice.</p>", SPARC_BANNER_ENABLED: value) do
          expect(SparcConfig.banner_enabled?).to be(true)
        end
      end
    end

    it "stays off when the flag is set but nothing supplies content" do
      with_env(SPARC_BANNER_HTML: nil, SPARC_BANNER_MESSAGE: nil, SPARC_BANNER_ENABLED: "true") do
        expect(SparcConfig.banner_enabled?).to be(false)
      end
    end

    it "tells the operator it is being ignored rather than failing silently" do
      allow(Rails.logger).to receive(:warn)

      with_env(SPARC_BANNER_HTML: "<p>Notice.</p>", SPARC_BANNER_ENABLED: "false") do
        SparcConfig.banner_enabled?
      end

      expect(Rails.logger).to have_received(:warn).with(/SPARC_BANNER_ENABLED is ignored/)
    end
  end

  describe "inline content is not a new trust path" do
    it "sanitizes it exactly as file content is sanitized" do
      hostile = '<p>Notice</p><script>alert("xss")</script><img src=x onerror="alert(1)">'

      with_env(SPARC_BANNER_HTML: hostile) do
        get login_path

        expect(response.body).to include("Notice")
        expect(response.body).not_to include("<script>")
        expect(response.body).not_to include("onerror")
      end
    end

    it "keeps the tags the banner legitimately needs" do
      with_env(SPARC_BANNER_HTML: '<p><strong>WARNING</strong></p><ul><li>Term one</li></ul>') do
        get login_path

        expect(response.body).to include("<strong>WARNING</strong>")
        expect(response.body).to include("<li>Term one</li>")
      end
    end
  end

  describe "precedence" do
    let(:banner_file) { Tempfile.new([ "banner", ".html" ]) }

    before do
      banner_file.write("<p>From the file.</p>")
      banner_file.rewind
    end

    after { banner_file.unlink }

    it "prefers inline content over the file path" do
      with_env(SPARC_BANNER_HTML: "<p>From the variable.</p>",
               SPARC_BANNER_MESSAGE: banner_file.path) do
        get login_path

        expect(response.body).to include("From the variable.")
        expect(response.body).not_to include("From the file.")
      end
    end

    it "says so in the log rather than silently discarding the other one" do
      allow(Rails.logger).to receive(:warn)

      with_env(SPARC_BANNER_HTML: "<p>From the variable.</p>",
               SPARC_BANNER_MESSAGE: banner_file.path) do
        get login_path
      end

      expect(Rails.logger).to have_received(:warn)
        .with(/Both SPARC_BANNER_HTML and SPARC_BANNER_MESSAGE are set/)
    end

    it "still loads from the file when only the path is set — unchanged behaviour" do
      with_env(SPARC_BANNER_HTML: nil, SPARC_BANNER_MESSAGE: banner_file.path) do
        get login_path

        expect(response.body).to include("From the file.")
      end
    end
  end

  describe "when the banner is on but nothing supplies content" do
    # The log assertion this example used to carry named a branch that was
    # already unreachable in production: banner_enabled? requires content, so
    # "enabled with no content" only ever occurred here, via the stub. #909
    # deleted the branch. The behaviour worth pinning is what remains — the page
    # still renders, and renders no banner.
    it "renders the page and no banner" do
      allow(SparcConfig).to receive(:banner_enabled?).and_return(true)

      with_env(SPARC_BANNER: nil, SPARC_BANNER_HTML: nil, SPARC_BANNER_MESSAGE: nil) do
        get login_path
      end

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("consentBannerLabel")
    end
  end

  # #909 — one variable, carrying the notice or a file: path to it.
  describe "SPARC_BANNER" do
    it "renders an unprefixed value as inline markup" do
      with_env(SPARC_BANNER: "<p>Authorized use only.</p>") do
        get login_path

        expect(response.body).to include("Authorized use only.")
      end
    end

    it "reads a file: prefixed value from disk" do
      file = Tempfile.new([ "banner", ".html" ])
      file.write("<p>From the file.</p>")
      file.rewind

      with_env(SPARC_BANNER: "file:#{file.path}") do
        get login_path

        expect(response.body).to include("From the file.")
      end
    ensure
      file.unlink
    end

    it "resolves a relative file: path against Rails.root" do
      with_env(SPARC_BANNER: "file:public/banners/dod-banner.html") do
        get login_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("consentBannerLabel")
      end
    end

    # The failure #867 designed against, and the reason the prefix is explicit
    # rather than inferred: a typo'd path must never become the notice.
    it "renders NOTHING — never the raw string — when the file: target is missing" do
      with_env(SPARC_BANNER: "file:public/banners/typo.html") do
        get login_path

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("public/banners/typo.html")
        expect(response.body).not_to include("consentBannerLabel")
      end
    end

    it "sanitizes inline markup through the same path as the file source" do
      with_env(SPARC_BANNER: '<p>Safe</p><script>alert("xss")</script>') do
        get login_path

        expect(response.body).to include("Safe")
        expect(response.body).not_to include("<script>alert")
      end
    end

    it "wins over the deprecated variables, and says so" do
      allow(Rails.logger).to receive(:warn)

      with_env(SPARC_BANNER: "<p>The new one.</p>",
               SPARC_BANNER_HTML: "<p>The old one.</p>",
               SPARC_BANNER_MESSAGE: nil) do
        get login_path

        expect(response.body).to include("The new one.")
        expect(response.body).not_to include("The old one.")
      end

      expect(Rails.logger).to have_received(:warn)
        .with(/SPARC_BANNER is set, so SPARC_BANNER_HTML is ignored/)
    end

    # Deprecated, but HONOURED — ignoring them would blank a legal notice on
    # upgrade for every deployment still setting them.
    it "still renders the notice when only the deprecated variables are set" do
      allow(Rails.logger).to receive(:warn)

      with_env(SPARC_BANNER: nil, SPARC_BANNER_HTML: "<p>Still here.</p>", SPARC_BANNER_MESSAGE: nil) do
        get login_path

        expect(response.body).to include("Still here.")
      end

      expect(Rails.logger).to have_received(:warn).with(/SPARC_BANNER_HTML is deprecated/)
    end
  end
end
