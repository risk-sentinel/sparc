# frozen_string_literal: true

require "rails_helper"

# The header's dropdowns, opened the way a person opens them — with a real
# browser, real Bootstrap, and the keyboard.
#
# The banner became one shared partial in #974, but nothing asserted that its
# menus still OPEN; the request specs only check which paths appear in the HTML.
# That gap is how four of the five toggles stayed `<a href="#" role="button">`
# after `_controls_nav` had already been converted to a real `<button>` with a
# comment explaining why. An anchor with a button role announces itself as a
# button and then ignores the Space key, because anchors have no native
# activation — so a keyboard-only or screen-reader user meets a control that
# says "button" and does nothing.
#
# Native <button> elements make that free. These tests are what proves it stays
# free: each toggle is found AS A BUTTON (`click_button` will not match an
# anchor) and one is opened with the keyboard alone.
RSpec.describe "Header nav dropdowns", type: :system do
  let(:admin) { create(:user, :admin) }

  before do
    visit "/login"
    accept_consent_banner
    fill_in "Email Address", with: admin.email
    fill_in "Password",      with: "SecurePassword123!"
    click_button "Sign In"

    expect(page).not_to have_field("Email Address", wait: 5),
      "Sign-in failed. Path=#{page.current_path}; body excerpt: #{page.body[0, 500]}"

    visit "/"
  end

  # 1.18.0-rf #1297 — the header is the shell header (shared/_shell_header):
  # Create, Library and Help are its menus. It does not collapse behind a
  # hamburger; below 768px the labels hide and the menus open full width.
  def resize(width, height = 1024)
    page.driver.browser.manage.window.resize_to(width, height)
  end

  def header = find("[data-testid=shell-header]")

  # Toggle label => a link that must become visible once it is open. A local,
  # not a constant: a constant assigned inside a describe block lands on Object
  # and leaks into every other spec in the run.
  menus = {
    "Create"  => "/ssp_documents/new",
    "Library" => "/control_catalogs",
    "Help"    => "/help"
  }

  menus.each do |toggle, href|
    it "opens #{toggle} on click and reveals its entries" do
      resize(1440)
      # click_button matches <button> and <input type=submit> only. An
      # `<a role="button">` fails here, which is the regression this catches.
      header.click_button toggle

      expect(header).to have_css("a[href='#{href}']", visible: true, wait: 3),
        "#{toggle} did not open, or its #{href} entry is missing"
    end
  end

  # The accessibility claim itself. An anchor never satisfies this: Space
  # scrolls the page instead of activating the control.
  it "opens a menu with the keyboard alone, no mouse" do
    resize(1440)
    header.find_button("Library").send_keys(:space)

    expect(header).to have_css("a[href='/control_catalogs']", visible: true, wait: 3),
      "the Library toggle did not respond to the Space key — it is not a native button"
  end

  # Hidden labels are fine at a phone's width; unreachable menus are not.
  it "reaches the same menus on a phone" do
    resize(390, 844)

    header.click_button "Library"
    expect(header).to have_css("a[href='/control_catalogs']", visible: true, wait: 3),
      "the Library menu must still open at a phone's width"
  end

  # The persistent controls stay in the bar at every width.
  it "keeps Help, the theme toggle and the account menu visible on a phone" do
    resize(390, 844)

    expect(header).to have_button("Help", visible: true),
      "Help must stay one click at every width — #880 built the drawer for mid-task lookups"
    expect(header).to have_css("[data-controller='theme'] button", visible: true),
      "the theme toggle must stay reachable at every width"
    expect(header).to have_css("button.sparc-nav-user", visible: true),
      "the account menu must stay reachable at every width"
  end
end
