# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1288 / #1289 — the shell preview exists only while the shell is
# being built: SPARC_NAV_SHELL on, signed in.
RSpec.describe "Shell preview", type: :request do
  let(:user) { create(:user) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  context "with SPARC_NAV_SHELL off (the default)" do
    before { sign_in_as(user) }

    it "is not found" do
      get shell_preview_path
      expect(response).to have_http_status(:not_found)
    end
  end

  context "with SPARC_NAV_SHELL on" do
    before { allow(SparcConfig).to receive(:nav_shell?).and_return(true) }

    it "sends a signed-out visitor to sign in" do
      get shell_preview_path
      expect(response).to redirect_to(login_path)
    end

    it "shows every building block and every icon to a signed-in user" do
      sign_in_as(user)
      get shell_preview_path

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      %w[.sparc-counter .sparc-tabs .sparc-segmented .sparc-filter-token .sparc-status-chip .sparc-action-group].each do |css|
        expect(page.at_css(css)).to be_present, "#{css} missing from the preview"
      end
      shown = page.css("[data-testid=shell-preview-icons] svg use").map { |u| u["href"].delete_prefix("#i-") }
      expect(shown).to match_array(IconHelper.names)
    end
  end

  it "reads the switch from SPARC_NAV_SHELL, off unless it is exactly true" do
    { nil => false, "false" => false, "1" => false, "true" => true }.each do |value, expected|
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SPARC_NAV_SHELL", "false").and_return(value || "false")
      expect(SparcConfig.nav_shell?).to be(expected), "SPARC_NAV_SHELL=#{value.inspect}"
    end
  end
end
