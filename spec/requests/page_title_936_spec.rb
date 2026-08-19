# frozen_string_literal: true

require "rails_helper"

# #936 — the layout must yield the title its templates already set.
#
# Nine views called `content_for :title` and no layout ever yielded it, so every
# browser tab read "SPARC" regardless of page. Nothing failed and nothing warned:
# `content_for` writes to a buffer, and a buffer nobody reads is indistinguishable
# from one that does not exist. The same silent shape as an unregistered audit
# action.
#
# Both directions are asserted deliberately. A spec that only checked the
# fallback would pass against a layout that ignores the yield entirely — which
# is exactly the state this fixes.
RSpec.describe "Page title (#936)", type: :request do
  # Declared here rather than inherited from the environment: CI configures no
  # auth method, and a spec that leans on `.env` asserts whatever that file
  # happens to say.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:user) { create(:user, :admin) }

  def title_of(body)
    body[%r{<title>(.*?)</title>}m, 1]&.strip
  end

  describe "a page that sets content_for :title" do
    it "renders that title, not the app name" do
      sign_in_as(user)

      get help_path

      expect(response).to have_http_status(:ok)
      expect(title_of(response.body)).to eq("Help &amp; User Guides")
    end

    # The regression that matters: two pages setting different titles must not
    # render the same one. A layout hardcoding a literal passes a single-page
    # assertion and fails this.
    it "differs between two pages that set different titles" do
      sign_in_as(user)

      get help_path
      first = title_of(response.body)

      get about_path
      second = title_of(response.body)

      expect(first).not_to eq(second)
      expect(second).to eq("About SPARC")
    end
  end

  describe "a page that sets no title" do
    it "falls back to the configured app name" do
      allow(SparcConfig).to receive(:app_name).and_return("Agency Compliance Hub")
      sign_in_as(user)

      get authorization_boundaries_path

      expect(title_of(response.body)).to eq("Agency Compliance Hub")
    end

    # A rebranded deployment must not leak "SPARC" into the tab. The literal
    # this replaced would have.
    it "does not hardcode SPARC" do
      allow(SparcConfig).to receive(:app_name).and_return("Agency Compliance Hub")
      sign_in_as(user)

      get authorization_boundaries_path

      expect(title_of(response.body)).not_to include("SPARC")
    end
  end
end
