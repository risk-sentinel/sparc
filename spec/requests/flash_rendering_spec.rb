# frozen_string_literal: true

require "rails_helper"

# #902 — the layouts rendered `success`, `error` and `warning` only, while
# Rails' own `redirect_to ..., notice:` / `alert:` shorthand writes `:notice`
# and `:alert`. 34 call sites across 12 controllers therefore set a flash that
# no user could ever see — including the evidence upload success message, which
# is why a working upload still looked like nothing had happened.
#
# The failure mode is what makes this worth a dedicated spec: nothing raised,
# nothing logged, and the controller specs asserting `flash[:notice] == "..."`
# all passed. Only rendering proves a message is readable, so these assertions
# go through the response BODY, never the flash hash.
RSpec.describe "Flash rendering", type: :request do
  let(:user) { create(:user, :admin) }

  # NOT a global `before` — `sign_in_as` stubs `current_user` on
  # ApplicationController rather than setting a cookie, so `reset!` cannot undo
  # it and the signed-out sign-in-layout case below would never redirect.
  def signed_in!
    sign_in_as(user)
  end

  # Catalog URLs canonicalise slug -> uuid with a 301 (#881), so a redirect
  # carrying a flash can take more than one hop before anything renders.
  def follow_redirects!
    follow_redirect! while response.redirect?
  end

  describe "keys the app actually sets" do
    # Drives a real controller that redirects with `notice:` rather than
    # stubbing one, so the spec breaks if that shorthand stops being rendered.
    it "renders a `notice:` redirect where the user can read it" do
      signed_in!
      catalog = create(:control_catalog)
      family  = create(:control_family, control_catalog: catalog)

      delete control_family_path(family)
      follow_redirects!

      expect(response.body).to include("Family was deleted.")
      expect(response.body).to include('data-flash-key="notice"')
    end

    it "renders an `alert:` redirect where the user can read it" do
      signed_in!
      get control_catalog_path("no-such-catalog")
      follow_redirects!

      expect(response.body).to include("Catalog not found")
      expect(response.body).to include('data-flash-key="alert"')
    end
  end

  # The sign-in screen uses its own layout, whose flash block is otherwise only
  # exercised by Chrome-gated system specs (pending on any machine without
  # Chrome, which includes local runs). Covering it here means the two layouts
  # cannot drift apart unnoticed.
  describe "the sign-in layout" do
    it "renders a flash redirected onto the login screen" do
      # The auth gate is a no-op when no login method is configured, which is
      # the default in test — without this stub the request never redirects and
      # the login layout is never rendered.
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)

      # Unauthenticated access to a protected page bounces to /login with a
      # warning; without a rendered flash the user is silently thrown out.
      get evidences_path
      follow_redirects!

      expect(response.body).to include("Please sign in to continue.")
      expect(response.body).to include('data-flash-key="warning"')
      expect(response.body).to include("alert-warning")
    end
  end

  describe "severity is conveyed to assistive technology" do
    it "announces errors assertively" do
      signed_in!
      get control_catalog_path("no-such-catalog")
      follow_redirects!

      # `alert:` maps to the danger style, which must interrupt.
      expect(response.body).to match(/data-flash-key="alert"[^>]*role="alert"/m)
      expect(response.body).to match(/data-flash-key="alert"[^>]*aria-live="assertive"/m)
      expect(response.body).to include("alert-danger")
    end

    it "announces non-errors politely" do
      signed_in!
      catalog = create(:control_catalog)
      family  = create(:control_family, control_catalog: catalog)

      delete control_family_path(family)
      follow_redirects!

      expect(response.body).to match(/data-flash-key="notice"[^>]*role="status"/m)
      expect(response.body).to match(/data-flash-key="notice"[^>]*aria-live="polite"/m)
      expect(response.body).to include("alert-success")
    end
  end
end
