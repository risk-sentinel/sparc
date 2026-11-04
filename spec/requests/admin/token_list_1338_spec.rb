# frozen_string_literal: true

require "rails_helper"

# #1338 — the user and service account pages list tokens from one partial:
# each token one entry with its name, status and buttons, then its facts as
# labelled pairs. No table, so nothing scrolls sideways.
RSpec.describe "Admin token list (#1338)", type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in_as(admin) }

  def page = Nokogiri::HTML(response.body)
  def entries = page.css("[data-testid=api-token-list] [data-testid=api-token]")
  def entry(name) = entries.find { _1.at_css(".sparc-token__title").text.include?(name) }
  def facts(el) = el.css(".sparc-token__fact").to_h { [ _1.at_css("dt").text.squish, _1.at_css("dd").text.squish ] }
  def buttons(el) = el.css(".sparc-token__actions a, .sparc-token__actions button, .sparc-token__actions input[type=submit]")
                      .map { (_1["value"].presence || _1.text).squish }

  def issue(user, name, **opts)
    ApiToken.generate!(user: user, name: name, created_by: admin, **opts)
  end

  shared_examples "a page listing tokens in one list" do
    it "draws no token table, and every token as one entry" do
      get path

      expect(page.css("table th").map(&:text)).not_to include("Last Used")
      expect(entries.size).to eq(2)
    end

    it "shows an active token's facts and its buttons" do
      live.update!(last_used_at: 2.hours.ago, last_used_ip: "10.20.4.18")
      get path

      active = entry("Live token")
      expect(active.at_css(".badge").text).to eq("Active")
      expect(facts(active)).to include(
        "Expires" => live.expires_at.strftime("%Y-%m-%d %H:%M UTC"),
        "Last used" => "about 2 hours ago, from 10.20.4.18",
        "Endpoints" => live.endpoint_summary.join("; "),
        "CIDRs" => "10.20.0.0/16"
      )
      expect(buttons(active)).to eq(expected_active_buttons)
      expect(active.at_css("[data-testid=edit-token-limits]")["href"]).to eq(edit_admin_user_api_token_path(account, live))
    end

    it "offers an expired token only what still applies, and says when it expired" do
      get path

      expired = entry("Old token")
      expect(expired.at_css(".badge").text).to eq("Expired")
      expect(facts(expired)).to include("Expired" => old.expires_at.strftime("%Y-%m-%d %H:%M UTC"), "Last used" => "Never",
                                        "CIDRs" => "Any address")
      expect(buttons(expired)).to eq(expected_expired_buttons)
    end
  end

  describe "a service account's page" do
    let(:account) { create(:user, service_account: true, owner: create(:user), display_name: "pipeline-sa") }
    let!(:live) { issue(account, "Live token", expires_at: 30.days.from_now, allowed_cidrs: [ "10.20.0.0/16" ]) }
    let!(:old) { issue(account, "Old token", expires_at: 30.days.from_now).tap { _1.update_columns(expires_at: 2.days.ago) } }
    let(:path) { admin_service_account_path(account) }
    let(:expected_active_buttons) { [ "Edit limits", "Renew", "Reissue" ] }
    let(:expected_expired_buttons) { [ "Reissue" ] }

    it_behaves_like "a page listing tokens in one list"

    it "stacks Account Details as a strip above the tokens" do
      get path

      strip = page.at_css("dl.sparc-detail-strip")
      expect(strip.css("dt").map(&:text)).to eq(%w[Status Owner Created])
      expect(page.css(".col-md-6")).to be_empty
    end

    it "does not offer Created or Revoke" do
      get path

      expect(facts(entry("Live token")).keys).not_to include("Created")
    end
  end

  describe "a user's page" do
    let(:account) { create(:user) }
    let!(:live) { issue(account, "Live token", expires_at: 30.days.from_now, allowed_cidrs: [ "10.20.0.0/16" ]) }
    let!(:old) { issue(account, "Old token", expires_at: 30.days.from_now).tap { _1.update_columns(expires_at: 2.days.ago) } }
    let(:path) { admin_user_path(account) }
    let(:expected_active_buttons) { [ "Edit limits", "Renew", "Reissue", "Revoke" ] }
    let(:expected_expired_buttons) { [ "Reissue", "Revoke" ] }

    it_behaves_like "a page listing tokens in one list"

    it "shows when each token was created" do
      get path

      expect(facts(entry("Live token"))["Created"]).to eq(live.created_at.strftime("%Y-%m-%d %H:%M UTC"))
    end
  end

  it "says so when an account holds no token" do
    get admin_user_path(create(:user))

    expect(entries).to be_empty
    expect(response.body).to include("No API tokens.")
  end
end
