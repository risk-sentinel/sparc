# frozen_string_literal: true

require "rails_helper"

# #784 — in-app Help Center. Thin HTML client of UserGuideLibrary.
RSpec.describe "Help Center", type: :request do
  let(:user) { create(:user) }

  before do
    sign_in_as(user)
    # The layout renders auth-gated nav; CI lacks the SPARC_ENABLE_* vars, so
    # stub the flag the layout reads (see feedback_local_env_vs_ci_drift).
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "GET /help" do
    it "renders the searchable guide index" do
      get help_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Help &amp; User Guides")
      expect(response.body).to include('data-controller="guide-search"')
      expect(response.body).to include("System Security Plans")
    end
  end

  describe "GET /help/:slug" do
    it "renders a guide" do
      get help_guide_path("system-security-plans")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("sparc-guide-content")
      # Image refs are rewritten to the in-app route, not the wiki-relative path.
      expect(response.body).not_to include('src="images/')
    end

    it "404s on an unknown guide" do
      get help_guide_path("no-such-guide")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /help/images/:filename" do
    it "serves a real guide screenshot inline" do
      get help_image_path("dashboard.png")

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("image/")
    end

    it "404s a missing image" do
      get help_image_path("does-not-exist.png")
      expect(response).to have_http_status(:not_found)
    end
  end
end
