# frozen_string_literal: true

require "rails_helper"

# Login-page caching + session-expiry hardening (#649, epic #650).
#
# Honours the single SPARC_SESSION_TIMEOUT_MINUTES var (no parallel timeout):
# the boundary tests time-travel the session rather than redefining the window.
RSpec.describe "Session security", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  describe "GET /login cache headers" do
    it "is served with Cache-Control: no-store so a stale (strict-CSP) copy " \
       "can't be restored from bfcache/HTTP cache" do
      get login_path

      cache_control = response.headers["Cache-Control"].to_s
      expect(cache_control).to include("no-store")
      expect(response.headers["Pragma"]).to eq("no-cache")
    end
  end

  describe "session cookie lifetime" do
    it "binds expire_after to the configured idle timeout (defense-in-depth " \
       "backstop to the app-level check)" do
      # Mirrors SparcConfig.session_timeout (default 60). The initializer reads
      # SPARC_SESSION_TIMEOUT_MINUTES directly to dodge the autoload-order trap.
      expect(Rails.application.config.session_options[:expire_after])
        .to eq(SparcConfig.session_timeout.minutes)
    end
  end

  describe "session timeout (check_session_timeout)" do
    let(:user) { create(:user) }

    before do
      sign_in_as(user)
      # Drive the app-level idle check at a SHORT boundary so it fires while the
      # session cookie (expire_after, fixed at boot to 60m) is still valid. This
      # isolates the app-level 303 path; the cookie-lifetime backstop is covered
      # separately above. Both honour SparcConfig.session_timeout — here we just
      # exercise the boundary deterministically by stubbing the configured value.
      allow(SparcConfig).to receive(:session_timeout).and_return(1)
    end

    it "stays signed in just before the configured boundary" do
      get root_path # 1st request stamps last_active_at into the session
      expect(response).to have_http_status(:ok)

      travel(30.seconds) do
        get root_path
        expect(response).to have_http_status(:ok)
      end
    end

    it "expires with a 303 to /login just past the configured boundary" do
      get root_path
      expect(response).to have_http_status(:ok)

      travel(2.minutes) do
        get root_path
        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(login_path)
      end
    end
  end
end
