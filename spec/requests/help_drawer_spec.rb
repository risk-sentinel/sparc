# frozen_string_literal: true

require "rails_helper"

# #880 — the in-page help drawer.
#
# What a request spec can prove is the server half: the drawer variant renders
# the SAME guide as the full page, as a bare Turbo Frame with no layout, and
# the trigger/panel markup a keyboard and screen-reader user depends on is
# actually emitted. The behaviour that only a browser can show — focus moving
# in and back out, Esc, unsaved input surviving, zero CSP violations on
# interaction — is driven in tests/ui-smoke/test_help_drawer_880.py.
RSpec.describe "Help drawer (#880)", type: :request do
  let(:user) { create(:user, admin: true) }

  before { sign_in_as(user) }

  # A slug that genuinely ships in the image, rather than a guessed one — a
  # 404 would make several of these assertions vacuously true.
  let(:slug) { UserGuideLibrary.all.first&.slug }

  before { skip "no User Guides ship in this checkout" if slug.blank? }

  describe "GET /help/:slug?drawer=1" do
    it "renders the guide as a bare Turbo Frame with no layout" do
      get help_guide_path(slug), params: { drawer: "1" }

      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      frame = doc.css("turbo-frame#help_drawer")
      expect(frame).not_to be_empty, "the drawer response must contain the frame it targets"

      # The frame is the whole response. If the layout leaked in, the drawer
      # would nest a second navbar and <body> inside the current page.
      expect(doc.css("nav.navbar")).to be_empty
      expect(response.body).not_to include("<!DOCTYPE html>")
    end

    it "renders the same guide body as the full page" do
      get help_guide_path(slug), params: { drawer: "1" }
      drawer_text = guide_text(response.body)

      get help_guide_path(slug)
      page_text = guide_text(response.body)

      expect(drawer_text).to be_present
      expect(drawer_text).to eq(page_text)
    end

    # The two views indent their wrapper differently, so the raw text differs
    # by leading whitespace alone. Collapse runs of whitespace — the claim
    # being pinned is that the CONTENT is the same guide, not that two ERB
    # templates happen to be indented alike.
    def guide_text(body)
      Nokogiri::HTML(body).css(".sparc-guide-content").text.gsub(/\s+/, " ").strip
    end

    it "404s an unknown slug rather than rendering an empty drawer" do
      get help_guide_path("no-such-guide"), params: { drawer: "1" }

      expect(response).to have_http_status(:not_found)
    end

    # The param is the switch. Anything else must fall through to the full
    # page, or a stray `?drawer=true` in a bookmark silently serves a
    # layout-less fragment as a whole screen.
    it "serves the full page unless drawer is exactly 1" do
      [ nil, "true", "0", "yes" ].each do |value|
        get help_guide_path(slug), params: value.nil? ? {} : { drawer: value }

        expect(response.body).to include("<!DOCTYPE html>"),
          "drawer=#{value.inspect} should render the full page"
      end
    end
  end

  describe "the drawer panel" do
    before { get authorization_boundaries_path }

    let(:doc) { Nokogiri::HTML(response.body) }
    let(:panel) { doc.at_css("#sparc-help-drawer") }

    it "is rendered on the page, ready for the trigger" do
      expect(panel).to be_present
    end

    it "carries an accessible name, so it is announced as a labelled dialog" do
      expect(panel["aria-labelledby"]).to eq("sparc-help-drawer-title")
      expect(doc.at_css("#sparc-help-drawer-title").text.strip).to be_present
    end

    it "is focusable as a panel — Bootstrap moves focus here on open" do
      expect(panel["tabindex"]).to eq("-1")
    end

    it "keeps the full guide reachable in a new tab from inside the drawer" do
      full = panel.at_css("[data-help-drawer-target='fullGuide']")

      expect(full).to be_present, "#880 keeps the full guide one click away"
      expect(full["target"]).to eq("_blank")
      expect(full["rel"].to_s).to include("noopener")
      expect(full.text).to match(/new tab/i), "the new tab must be announced, not just implied"
    end

    it "starts with an empty frame so no page pays for a guide nobody opened" do
      frame = panel.at_css("turbo-frame#help_drawer")

      expect(frame).to be_present
      expect(frame["src"]).to be_nil
    end

    it "wires the navbar trigger to the drawer with no inline handler" do
      trigger = doc.css("a.sparc-nav-btn").find { |a| a["data-action"].to_s.include?("help-drawer#open") }

      expect(trigger).to be_present, "the navbar ? must open the drawer"
      expect(trigger.attributes.keys.grep(/\Aon/i)).to be_empty,
        "an inline handler would be blocked outright — CSP has no 'unsafe-inline'"
    end

    it "mounts the controller on an element containing both the trigger and the panel" do
      # Scoping bug this catches: put data-controller on the navbar and the
      # panel falls outside it, so the target lookup finds nothing and the "?"
      # silently does nothing.
      expect(doc.at_css("body")["data-controller"].to_s).to include("help-drawer")
    end
  end

  describe "when nobody is signed in" do
    it "renders no drawer, matching the trigger it belongs to" do
      # The panel and the "?" are gated on the same condition. If they ever
      # diverge, a signed-out page ships a dialog with nothing to open it.
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
      delete logout_path

      get login_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("#sparc-help-drawer")).to be_nil
      expect(doc.css("a.sparc-nav-btn").select { |a| a["href"].to_s.include?("/help") }).to be_empty
    end
  end
end
