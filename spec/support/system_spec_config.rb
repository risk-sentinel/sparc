# frozen_string_literal: true

# Layer 1 of the UI test net (#572). System specs use Capybara + headless
# Chrome (Selenium) so real CSS / JS / CSP behavior is exercised. This is
# the layer that would have caught the v1.7.0 Okta-tab CSP regression at
# PR time — the inline onclick attributes were silently blocked by the
# enforced CSP, which only a real browser surfaces.
#
# Browser dependency:
#   - CI: .github/workflows/ci.yml installs google-chrome-stable
#         alongside the Ruby toolchain, so system specs run there.
#   - Local dev: Chrome / Chromium must be on PATH. Specs auto-skip with
#         a clear message when no browser is found, so the rest of the
#         suite stays runnable without the heavy browser dep.
#
# CSP-in-tests:
#   - config/initializers/content_security_policy.rb has no env guards,
#     so the same enforced CSP headers prod sends are present in test.
#     Headless Chrome enforces them. A controller / view that depends
#     on inline event handlers, unnonced inline scripts, or unsafe-eval
#     will fail a system spec before it hits production.

require "capybara/rails"
require "capybara/rspec"
require "selenium/webdriver"

# Detect a usable Chrome / Chromium binary. nil → skip system specs.
def sparc_chrome_binary
  ENV["SPARC_TEST_CHROME_BIN"].presence ||
    %w[
      google-chrome
      google-chrome-stable
      chromium
      chromium-browser
      /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome
    ].find { |b| system("command -v #{Shellwords.escape(b)} >/dev/null 2>&1") || File.executable?(b) }
end

Capybara.register_driver :sparc_headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--disable-gpu")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--window-size=1280,1024")
  bin = sparc_chrome_binary
  options.binary = bin if bin && File.executable?(bin)

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.configure do |config|
  config.javascript_driver = :sparc_headless_chrome
  config.default_driver    = :sparc_headless_chrome
  config.default_max_wait_time = 5
  config.server = :puma, { Silent: true }
end

# Helper for the mandatory login consent banner (#190). The banner is forced
# ON for every system spec (see the before-each below) so the consent screen
# is always exercised in the real flow, independent of a developer's local
# .env. It renders a Bootstrap modal over a hidden (d-none) login card;
# `accept_consent_banner` performs the real "Proceed" click that reveals the
# login form (consent_banner_controller#proceed). Call it right after visiting
# a page that shows the banner (e.g. /login), before touching the login form.
module SystemConsentBanner
  def accept_consent_banner
    return unless page.has_button?("Proceed", wait: 5)

    click_button "Proceed"
    # proceed() synchronously un-hides the login card (so the form is ready)
    # and calls bsModal.hide(). But in headless Chrome the Bootstrap fade-out's
    # `transitionend` can fail to fire, so hide() never completes its DOM
    # teardown — the `.modal.show` element and `.modal-backdrop` linger and
    # intercept clicks on the now-visible login form. Finish the teardown
    # explicitly (the real consent→reveal already happened via #proceed).
    page.execute_script(<<~JS)
      document.querySelectorAll(".modal.show").forEach((m) => {
        m.classList.remove("show");
        m.style.display = "none";
        m.setAttribute("aria-hidden", "true");
      });
      document.querySelectorAll(".modal-backdrop").forEach((el) => el.remove());
      document.body.classList.remove("modal-open");
      document.body.style.overflow = "";
    JS
    expect(page).to have_no_css(".modal.show")
    expect(page).to have_no_css(".modal-backdrop")
  end
end

RSpec.configure do |config|
  # System specs run a Puma server in a separate thread; RSpec mocks
  # are thread-local, so `allow(SparcConfig).to receive(...)` stubs
  # set up in the spec thread don't reach the controller in the
  # server thread. Flip the underlying env vars instead — those are
  # process-wide and SparcConfig methods read them fresh each call.
  # Snapshot original env at example start; restore after.
  AUTH_ENV_KEYS = %w[SPARC_ENABLE_LOCAL_LOGIN SPARC_ENABLE_OIDC
                     SPARC_ENABLE_LDAP SPARC_OIDC_PROVIDER_TITLE
                     SPARC_OIDC_ISSUER_URL SPARC_OIDC_CLIENT_ID
                     SPARC_BANNER_ENABLED SPARC_BANNER_MESSAGE].freeze

  config.include SystemConsentBanner, type: :system

  config.before(:each, type: :system) do |example|
    if sparc_chrome_binary.nil?
      skip "No Chrome/Chromium on PATH. Install one to run system specs locally; " \
           "CI installs google-chrome-stable automatically."
    end
    driven_by :sparc_headless_chrome

    # Snapshot for after-each restore (isolates specs from a developer's .env).
    example.metadata[:_sparc_env_snapshot] = AUTH_ENV_KEYS.index_with { |k| ENV[k] }

    # Sensible defaults so admin nav specs can form-sign-in. Override
    # per-example by setting ENV[...] in the spec's own before block.
    ENV["SPARC_ENABLE_LOCAL_LOGIN"] = "true"

    # The login consent banner (#190) is a MANDATORY consent screen — force it
    # on for all system specs so the real banner→Proceed→login flow is always
    # covered, regardless of whether the developer's local .env enables it.
    # Specs dismiss it via `accept_consent_banner`. Points at the in-repo DoD
    # banner file (resolved against Rails.root by SessionsController).
    ENV["SPARC_BANNER_ENABLED"] = "true"
    ENV["SPARC_BANNER_MESSAGE"] = "public/banners/dod-banner.html"
  end

  config.after(:each, type: :system) do |example|
    snapshot = example.metadata[:_sparc_env_snapshot] || {}
    snapshot.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
