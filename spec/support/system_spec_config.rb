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

RSpec.configure do |config|
  # System specs run a Puma server in a separate thread; RSpec mocks
  # are thread-local, so `allow(SparcConfig).to receive(...)` stubs
  # set up in the spec thread don't reach the controller in the
  # server thread. Flip the underlying env vars instead — those are
  # process-wide and SparcConfig methods read them fresh each call.
  # Snapshot original env at example start; restore after.
  AUTH_ENV_KEYS = %w[SPARC_ENABLE_LOCAL_LOGIN SPARC_ENABLE_OIDC
                     SPARC_ENABLE_LDAP SPARC_OIDC_PROVIDER_TITLE
                     SPARC_OIDC_ISSUER_URL SPARC_OIDC_CLIENT_ID].freeze

  config.before(:each, type: :system) do |example|
    if sparc_chrome_binary.nil?
      skip "No Chrome/Chromium on PATH. Install one to run system specs locally; " \
           "CI installs google-chrome-stable automatically."
    end
    driven_by :sparc_headless_chrome

    # Snapshot for after-each restore.
    example.metadata[:_sparc_env_snapshot] = AUTH_ENV_KEYS.index_with { |k| ENV[k] }

    # Sensible defaults so admin nav specs can form-sign-in. Override
    # per-example by setting ENV[...] in the spec's own before block.
    ENV["SPARC_ENABLE_LOCAL_LOGIN"] = "true"
  end

  config.after(:each, type: :system) do |example|
    snapshot = example.metadata[:_sparc_env_snapshot] || {}
    snapshot.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
