# frozen_string_literal: true

require "rails_helper"

# #936 — the icon links and link-preview metadata the layouts now serve.
#
# A saved SPARC URL showed the browser's generic globe because no icon `<link>`
# existed and the browser's fallback, `/favicon.ico`, did not either. A SPARC
# link pasted into Slack rendered as bare text because nothing served `og:`.
#
# The assertions that carry weight here are the ABSOLUTE ones. Every consumer of
# `og:image` fetches it from another host, so a relative path resolves against
# nothing and the card renders blank — a failure invisible from inside the app.
RSpec.describe "Link preview and icons (#936)", type: :request do
  # Declared, not inherited: CI configures no auth method, and a spec that leans
  # on `.env` asserts whatever that file happens to say.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:user) { create(:user, :admin) }

  def head_of(body) = body[%r{<head>(.*?)</head>}m, 1].to_s

  describe "icon links" do
    it "declares the ico, svg and apple-touch icons on an authenticated page" do
      sign_in_as(user)

      get authorization_boundaries_path
      head = head_of(response.body)

      expect(head).to include(%(<link rel="icon" href="/favicon.ico" sizes="32x32">))
      expect(head).to include(%(<link rel="icon" href="/icon.svg" type="image/svg+xml">))
      expect(head).to include(%(<link rel="apple-touch-icon" href="/apple-touch-icon.png">))
    end

    # The login screen is the most-shared SPARC URL and the first one anybody
    # bookmarks, so it must not be the one screen missing its icons.
    it "declares them on the signed-out login page too" do
      get login_path

      expect(head_of(response.body)).to include(%(rel="apple-touch-icon"))
    end
  end

  describe "the files themselves" do
    # The layout can be perfect and the icons still 404. These are static files
    # in `public/`, so their existence is the contract.
    it "ships every icon the layout points at" do
      %w[favicon.ico icon.svg icon.png apple-touch-icon.png og-preview.png].each do |name|
        expect(Rails.public_path.join(name)).to exist, "public/#{name} is missing"
      end
    end

    # The acceptance criterion #936 states outright.
    it "no longer ships the stock Rails red-circle placeholder" do
      svg = Rails.public_path.join("icon.svg").read

      expect(svg).to include("data:image/png;base64,")
      expect(svg).not_to match(/<circle[^>]*fill="red"/)
    end
  end

  describe "Open Graph and Twitter metadata" do
    it "serves the card tags" do
      sign_in_as(user)

      get authorization_boundaries_path
      head = head_of(response.body)

      expect(head).to include(%(property="og:type" content="website"))
      expect(head).to include(%(name="twitter:card" content="summary_large_image"))
      expect(head).to include(%(property="og:image:width" content="1200"))
    end

    # The load-bearing one. A relative og:image renders a blank card on every
    # consumer, and nothing inside the app would show it.
    it "makes og:url and og:image absolute" do
      sign_in_as(user)

      get authorization_boundaries_path
      head = head_of(response.body)

      og_image = head[/property="og:image" content="([^"]+)"/, 1]
      og_url   = head[/property="og:url" content="([^"]+)"/, 1]

      expect(og_image).to start_with("http")
      expect(og_image).to end_with("/og-preview.png")
      expect(og_url).to start_with("http")
    end

    it "titles the card with the page, and names the site with the app" do
      sign_in_as(user)

      get about_path
      head = head_of(response.body)

      expect(head).to include(%(property="og:title" content="About SPARC"))
      expect(head).to include(%(property="og:site_name" content="SPARC"))
    end

    # A rebranded deployment must not publish "SPARC" into every link its staff
    # share — the same leak #991 fixed in the browser tab.
    it "uses the configured app name rather than a hardcoded one" do
      allow(SparcConfig).to receive(:app_name).and_return("Agency Compliance Hub")
      sign_in_as(user)

      get authorization_boundaries_path
      head = head_of(response.body)

      expect(head).to include(%(property="og:site_name" content="Agency Compliance Hub"))
      expect(head).not_to include(%(content="SPARC"))
    end
  end
end
