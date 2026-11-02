# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1306 — a skip link to the page's <main> on every layout, and the
# problems axe found on today's pages (2026-11-02) that are not colour:
# dropdowns a screen reader could not name, and a button inside the control
# that opens and closes the Data Quality card.
RSpec.describe "Accessible names and controls (#1306)", type: :request do
  def page = Nokogiri::HTML(response.body)

  # The text of the <label> that names the control, or nil.
  def label_for(id)
    page.at_css("label[for='#{id}']")&.text&.squish
  end

  let(:admin) { create(:user, :admin) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "the skip link and the main landmark" do
    # The skip link is the first link on the page and leads to the one <main>.
    def expect_skip_link_to_main
      first_link = page.at_css("body a[href]")
      expect(first_link["data-testid"]).to eq("skip-link")
      expect(first_link.text.squish).to eq("Jump to page content")
      expect(page.css("main").size).to eq(1)
      expect(first_link["href"]).to eq("##{page.at_css('main')['id']}")
      expect(page.at_css("main")["tabindex"]).to eq("-1")
    end

    it "leads past the header on an ordinary page, with the page inside <main>" do
      sign_in_as(admin)
      get authoritative_sources_path

      expect_skip_link_to_main
      expect(page.at_css("main h1, main [data-testid=page-header]")).to be_present
      expect(page.css("main nav[aria-label='Main']")).to be_empty
    end

    it "leads past the header on an administration page, settings menu included" do
      sign_in_as(admin)
      get admin_users_path

      expect_skip_link_to_main
      expect(page.at_css("main [data-testid=page-header]")).to be_present
    end

    it "leads past the header on the sign-in page" do
      get login_path

      expect_skip_link_to_main
      expect(page.at_css("main h1").text).to start_with("Welcome to SPARC")
    end
  end

  it "names both filter dropdowns on Authoritative Sources" do
    sign_in_as(admin)
    get authoritative_sources_path

    %w[scope rel].each { |field| expect(page.at_css("select##{field}")).to be_present, field }
    expect(label_for("scope")).to eq("Scope")
    expect(label_for("rel")).to eq("Relationship")
  end

  it "points each New SAP label at its dropdown" do
    sign_in_as(admin)
    get new_sap_document_path

    %w[ssp-select profile-select].each { |id| expect(page.at_css("select##{id}")).to be_present, id }
    expect(label_for("ssp-select")).to start_with("System Security Plan (SSP)")
    expect(label_for("profile-select")).to start_with("Baseline Profile")
  end

  it "keeps Re-validate outside the control that opens the Data Quality card" do
    catalog = create(:control_catalog, status: "completed")
    sign_in_as(admin)
    get control_catalog_path(catalog)
    follow_redirect! while response.redirect?

    card = page.at_css(".data-quality-card")
    expect(card.at_css("summary")).to be_present
    expect(card.css("summary button, summary a, summary input")).to be_empty
    expect(card.at_css(".data-quality-card__actions button").text.squish).to eq("Re-validate")
  end
end
