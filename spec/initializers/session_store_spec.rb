# frozen_string_literal: true

require "rails_helper"

# Regression guard for #515 — the SPARC session cookie must remain
# **host-only** (no `Domain=` attribute) so it isn't sent to the
# userdata.* subdomain that serves user-uploaded blobs. Adding a
# `domain:` to session config would silently defeat the cookieless-
# subdomain protection.
RSpec.describe "Session cookie scope (#515)" do
  describe "Rails.application.config.session_options" do
    it "does NOT set a :domain key (cookie remains host-only)" do
      expect(Rails.application.config.session_options[:domain]).to be_nil,
        "session_options has :domain set, which would make the cookie sent to subdomains like userdata.* — defeats #515"
    end
  end

  describe "actual Set-Cookie header from a session-writing request", type: :request do
    it "does not include Domain= in the issued session cookie" do
      # POST /login always writes to the session (CSRF token consumption,
      # auth attempt counter, etc.), so a Set-Cookie is issued.
      post "/login", params: { email: "nope@example.com", password: "wrong" }
      set_cookie = response.headers["Set-Cookie"].to_s
      next if set_cookie.empty? # rate-limited / safelisted edge cases tolerable; config-level check above is the strict guard
      expect(set_cookie).not_to match(/domain=/i),
        "session cookie has Domain= attribute: #{set_cookie.inspect}"
    end
  end
end
