# frozen_string_literal: true

require "rails_helper"

# #860 — the ABSOLUTE session cap (SPARC_SESSION_MAX_HOURS, default 8).
#
# `SPARC_SESSION_TIMEOUT_MINUTES` is an IDLE timeout: `last_active_at` is
# refreshed on every request, so a user who keeps working is never asked to
# authenticate again. Entitlements are resolved at login (#860's model), so
# without an absolute cap they stay in force for as long as the session does —
# which, for an active user, is unbounded. This is the control that bounds it.
#
# ── Why these examples run on a COMPRESSED clock ────────────────────────────
#
# The session COOKIE carries its own `expire_after`, fixed at boot to
# SPARC_SESSION_TIMEOUT_MINUTES (60). Travel further than that between two
# requests and the integration session simply drops the cookie, so the next
# request arrives with a BRAND NEW empty session — and because `sign_in_as`
# stubs `signed_in?`, the application never notices and answers 200.
#
# An 8-hour example written the obvious way therefore proves nothing: it passes
# whether or not the cap exists, because the thing it expires is a session the
# test already threw away. So the cap is stubbed to 1 hour and every jump is
# kept under the cookie's 60 minutes. The DEFAULT of 8 is asserted separately —
# the mechanism is unit-agnostic, and the value is a one-line fact.
RSpec.describe "Absolute session cap", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "the configured default" do
    it "is 8 hours — a working day, so a user who signs in at the start of one " \
       "is asked again the next" do
      expect(SparcConfig.session_max_hours).to eq(8)
    end

    it "can be provisioned per instance" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SPARC_SESSION_MAX_HOURS", "8").and_return("12")

      expect(SparcConfig.session_max_hours).to eq(12)
    end
  end

  describe "the session start stamp" do
    it "is recorded once and NOT refreshed by activity" do
      # The property that makes this an absolute cap rather than a second idle
      # timeout. `last_active_at` moves with every request; `started_at` must
      # not, or the cap resets whenever the user does anything and can never
      # fire for the active user it exists to bound.
      get root_path
      started = session[:started_at]
      first_active = session[:last_active_at]
      expect(started).to be_present

      travel(30.minutes) do
        get root_path

        expect(session[:started_at]).to eq(started),
          "started_at moved with activity, so the cap resets and never fires"
        expect(session[:last_active_at]).to be > first_active,
          "last_active_at did not refresh, so this is not measuring what it should"
      end
    end
  end

  describe "a session that stays continuously ACTIVE" do
    before { allow(SparcConfig).to receive(:session_max_hours).and_return(1) }

    it "survives right up to the cap" do
      get root_path
      expect(response).to have_http_status(:ok)

      [ 30, 55 ].each do |minutes|
        travel(minutes.minutes) do
          get root_path
          expect(response).to have_http_status(:ok),
            "expired at #{minutes}m, inside the 1h cap"
        end
      end
    end

    it "is terminated once past it, however active the user has been" do
      get root_path

      travel(45.minutes) do
        get root_path
        expect(response).to have_http_status(:ok)
      end

      # Only 20 minutes since the last request, so the 60-minute IDLE timeout
      # cannot be what fires here. This is the absolute cap and nothing else.
      travel(65.minutes) do
        get root_path

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(login_path)
      end
    end
  end

  describe "when disabled with SPARC_SESSION_MAX_HOURS=0" do
    before { allow(SparcConfig).to receive(:session_max_hours).and_return(0) }

    it "restores the idle-only behaviour, so activity alone keeps a session alive" do
      get root_path

      [ 30, 55, 80, 105 ].each do |minutes|
        travel(minutes.minutes) do
          get root_path
          expect(response).to have_http_status(:ok),
            "expired at #{minutes}m with the cap disabled"
        end
      end
    end
  end

  describe "the two limits are independent" do
    it "an IDLE session still expires well inside the absolute cap" do
      allow(SparcConfig).to receive(:session_timeout).and_return(1)
      allow(SparcConfig).to receive(:session_max_hours).and_return(8)

      get root_path
      expect(response).to have_http_status(:ok)

      travel(2.minutes) do
        get root_path
        expect(response).to redirect_to(login_path)
      end
    end
  end
end
