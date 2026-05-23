# frozen_string_literal: true

require "rails_helper"

# Verifies the CSP header is sent in enforcing mode (#514) — promoted from
# report-only as part of v1.7.0. Public /login page is the simplest target
# since it requires no auth setup and renders the layout with the standard
# CSP-injecting middleware chain.
RSpec.describe "Content-Security-Policy header (#514)", type: :request do
  it "sends Content-Security-Policy (enforcing), not Content-Security-Policy-Report-Only" do
    get "/login"
    expect(response.headers["Content-Security-Policy"]).to be_present
    expect(response.headers["Content-Security-Policy-Report-Only"]).to be_blank
  end

  it "includes a script-src nonce directive in the enforced header" do
    get "/login"
    csp = response.headers["Content-Security-Policy"]
    expect(csp).to match(/script-src[^;]*'nonce-[^']+'/)
  end

  it "includes the configured default-src 'self'" do
    get "/login"
    csp = response.headers["Content-Security-Policy"]
    expect(csp).to match(/default-src 'self'/)
  end

  it "includes object-src 'none' (no plugins allowed)" do
    get "/login"
    csp = response.headers["Content-Security-Policy"]
    expect(csp).to match(/object-src 'none'/)
  end

  it "includes frame-ancestors 'self' (clickjacking defense)" do
    get "/login"
    csp = response.headers["Content-Security-Policy"]
    expect(csp).to match(/frame-ancestors 'self'/)
  end

  describe "rendered HTML matches the header nonce" do
    it "every inline <script> tag in the login layout carries the same nonce as the header advertises" do
      get "/login"
      csp = response.headers["Content-Security-Policy"]
      header_nonce = csp.match(/script-src[^;]*'nonce-([^']+)'/)&.captures&.first
      expect(header_nonce).to be_present, "expected script-src to include a nonce-<value>; got: #{csp}"

      # Find every inline <script ...>...</script> block (omit <script src="...">)
      inline_scripts = response.body.scan(/<script\b(?![^>]*\bsrc=)([^>]*)>/i)
      expect(inline_scripts).not_to be_empty, "expected at least one inline <script> in the login page"

      inline_scripts.each do |attrs_string|
        attrs = attrs_string.first.to_s
        next if attrs.include?('nonce="')  # nonce'd inline script
        next if attrs.include?("nonce='")
        # If we reach here, an inline <script> without nonce is present —
        # the browser would block it under the enforced CSP.
        raise "found inline <script> without nonce attribute in /login response: #{attrs.inspect}"
      end

      # And the nonce on each script must match the one in the header.
      inline_scripts.each do |attrs_string|
        attrs = attrs_string.first.to_s
        tag_nonce = attrs.match(/nonce=["']([^"']+)["']/)&.captures&.first
        next unless tag_nonce
        expect(tag_nonce).to eq(header_nonce), "inline <script> nonce #{tag_nonce.inspect} does not match header nonce #{header_nonce.inspect}"
      end
    end
  end
end
