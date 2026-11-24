# frozen_string_literal: true

require "rails_helper"

# #1396 — every system spec starts in a clean browser. Capybara resets the
# browser between examples; on Chrome 158 that reset failed and the next
# example started with the previous example's session cookie, so a spec could
# pass signed in as a user it never signed in as. This drives the same reset
# Capybara runs between examples and checks what is left behind.
RSpec.describe "System test isolation", type: :system do
  let(:admin) { create(:user, :admin) }

  def browser_cookies
    page.driver.browser.execute_cdp("Storage.getCookies")["cookies"]
  end

  it "runs the pinned Chrome" do
    visit "/login"
    expect(page.driver.browser.capabilities.browser_version).to eq(SPARC_TEST_CHROME_VERSION)
  end

  it "leaves no session cookie or local storage behind after a reset" do
    visit "/login"
    accept_consent_banner
    fill_in "Email Address", with: admin.email
    fill_in "Password", with: "SecurePassword123!"
    click_button "Sign In"
    expect(page).not_to have_field("Email Address", wait: 5)
    visit "/admin/users"
    expect(page).to have_current_path("/admin/users")
    page.execute_script("window.localStorage.setItem('sparc.isolation.probe', '1')")
    expect(browser_cookies.map { |c| c["name"] }).to include("_ssp_tpr_manager_session")

    Capybara.reset_sessions!

    expect(browser_cookies).to be_empty
    visit "/admin/users"
    expect(page).to have_current_path("/login", ignore_query: true)
    expect(page.evaluate_script("window.localStorage.getItem('sparc.isolation.probe')")).to be_nil
  end
end
