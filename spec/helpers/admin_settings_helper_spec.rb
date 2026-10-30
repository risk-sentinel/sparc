# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1303 — the settings menu beside admin screens is shown only to
# whoever those screens admit. A refused request redirects before any page
# renders, so this is a second guard; it is tested here, where it can fail.
RSpec.describe AdminSettingsHelper, type: :helper do
  before { allow(helper).to receive(:controller_path).and_return("admin/audit_logs") }

  it "shows the menu on an admin screen to someone admin_access? admits" do
    allow(helper).to receive(:admin_access?).and_return(true)
    expect(helper.admin_settings_page?).to be(true)
  end

  it "never shows it to anyone else, even on an admin screen" do
    allow(helper).to receive(:admin_access?).and_return(false)
    expect(helper.admin_settings_page?).to be(false)
  end

  it "is not shown outside the admin screens" do
    allow(helper).to receive_messages(controller_path: "ssp_documents", admin_access?: true)
    expect(helper.admin_settings_page?).to be(false)
  end

  it "lists each admin screen once" do
    paths = helper.admin_settings_sections.flat_map(&:items).map(&:path)
    expect(paths).to eq(paths.uniq)
    expect(paths.size).to eq(10)
  end
end
