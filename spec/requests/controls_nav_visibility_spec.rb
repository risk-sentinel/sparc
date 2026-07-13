# frozen_string_literal: true

require "rails_helper"

# #726 — the Controls layer (catalogs, baselines, mappings) must be hidden and
# read-gated for unauthenticated users when auth is enabled, unless a deployment
# opts into public sharing via SPARC_PUBLIC_CATALOGS. (NIST AC-3)
RSpec.describe "Controls layer visibility (#726)", type: :request do
  let(:user) { create(:user) }
  let(:controls_marker) { "sparc-nav-controls" }

  # Index paths for the three Controls-layer read controllers.
  READ_PATHS = {
    "catalogs"  => "/control_catalogs",
    "baselines" => "/profile_documents",
    "mappings"  => "/control_mappings"
  }.freeze

  def enable_auth(public_catalogs:)
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:public_catalogs?).and_return(public_catalogs)
  end

  describe "read access" do
    context "when auth is enabled and SPARC_PUBLIC_CATALOGS is off (secure-by-default)" do
      before { enable_auth(public_catalogs: false) }

      READ_PATHS.each do |label, path|
        it "redirects an unauthenticated guest away from #{label}" do
          get path
          expect(response).to have_http_status(:found)
          expect(response).to redirect_to(login_path)
        end

        it "allows a signed-in user to read #{label}" do
          sign_in_as(user)
          get path
          expect(response).to have_http_status(:ok)
        end
      end
    end

    context "when SPARC_PUBLIC_CATALOGS is on" do
      before { enable_auth(public_catalogs: true) }

      READ_PATHS.each do |label, path|
        it "allows an unauthenticated guest to read #{label}" do
          get path
          expect(response).to have_http_status(:ok)
        end
      end
    end

    context "when no auth method is enabled (backward compatible)" do
      before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(false) }

      READ_PATHS.each do |label, path|
        it "allows an unauthenticated guest to read #{label}" do
          get path
          expect(response).to have_http_status(:ok)
        end
      end
    end
  end

  describe "header Controls dropdown visibility" do
    before { allow(SparcConfig).to receive(:enable_local_login?).and_return(true) }

    it "is hidden on the login page for a guest when auth is on and sharing is off" do
      enable_auth(public_catalogs: false)
      get login_path
      expect(response.body).not_to include(controls_marker)
    end

    it "is shown on the login page when SPARC_PUBLIC_CATALOGS is on" do
      enable_auth(public_catalogs: true)
      get login_path
      expect(response.body).to include(controls_marker)
    end

    it "is shown for a signed-in user" do
      enable_auth(public_catalogs: false)
      sign_in_as(user)
      get "/control_catalogs"
      expect(response.body).to include(controls_marker)
    end
  end
end
