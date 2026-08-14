# frozen_string_literal: true

require "rails_helper"

# #881's canonicalisation redirects dropped the request FORMAT.
#
# `/control_catalogs/783.json` 301'd to `/control_catalogs/<uuid>` — no
# `.json` — and because fetch() follows redirects transparently, the caller
# received a full HTML page where it had asked for JSON. `response.json()` threw,
# and "Create Profile from Catalog" reported "Failed to load controls. Try
# again." for every catalog, with nothing in the log to explain it.
#
# The screen was completely broken and every layer was green: the route existed,
# the controller worked, the JSON view worked, and the redirect was a correct
# 301 to a correct URL. Only the COMBINATION failed. So these specs assert the
# thing that actually broke — that a JSON request stays JSON across the
# redirect — rather than that the redirect happens.
RSpec.describe "Canonical URL redirects preserve the request format (#881)", type: :request do
  let(:user) { create(:user, admin: true) }

  before { sign_in_as(user) }

  let!(:catalog) do
    create(:control_catalog, oscal_uuid: SecureRandom.uuid).tap do |c|
      family = create(:control_family, control_catalog: c)
      create(:catalog_control, control_family: family)
    end
  end

  describe "GET /control_catalogs/:numeric_id.json" do
    it "redirects to the canonical URL with .json intact" do
      get "/control_catalogs/#{catalog.id}.json"

      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers["Location"]).to end_with(".json"),
        "the redirect dropped the format — the caller will silently receive HTML"
    end

    it "delivers JSON, not an HTML page, after following the redirect" do
      # The end-to-end property the browser actually experiences.
      get "/control_catalogs/#{catalog.id}.json"
      follow_redirect!

      expect(response.media_type).to eq("application/json"),
        "asked for JSON and got #{response.media_type} — this is the bug"
      expect { JSON.parse(response.body) }.not_to raise_error
    end

    it "returns the control families the catalog picker needs" do
      # family_selector_controller reads data.control_families. An empty or
      # absent key renders a picker with nothing in it, which looks like a
      # catalog with no controls rather than a broken response.
      get "/control_catalogs/#{catalog.id}.json"
      follow_redirect!

      body = JSON.parse(response.body)
      expect(body).to have_key("control_families")
      expect(body["control_families"]).to be_present
    end
  end

  describe "the HTML path is unchanged" do
    it "does not append a format to ordinary page redirects" do
      # params[:format] is nil for HTML, so the redirect must not become
      # `/control_catalogs/<uuid>.html`.
      get "/control_catalogs/#{catalog.id}"

      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers["Location"]).not_to end_with(".html")
      expect(response.headers["Location"]).to include(catalog.oscal_uuid)
    end

    it "still lands on a working page" do
      get "/control_catalogs/#{catalog.id}"
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
    end
  end

  describe "the canonical URL itself does not redirect" do
    it "serves JSON directly with no 301" do
      get "/control_catalogs/#{catalog.oscal_uuid}.json"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end
  end
end
