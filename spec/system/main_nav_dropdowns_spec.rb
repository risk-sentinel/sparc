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

  # The shared driver runs at 1280x1024, and #1042 moved the navbar to
  # `navbar-expand-xxl` — so below 1400px the nav LINKS collapse into the
  # hamburger and `click_button "Implementation"` finds nothing visible.
  #
  # These examples are about the toggles being native <button> elements that
  # answer the Space key (#974), not about the breakpoint, so they are given a
  # viewport where the bar is expanded. Resized per-example rather than by
  # changing the global driver, which every other system spec shares.
  #
  # The collapsed path is not dropped — it is asserted separately below.
  def resize(width, height = 1024)
    page.driver.browser.manage.window.resize_to(width, height)
  end

  # Toggle label => an item that must become visible once it is open. A local,
  # not a constant: a constant assigned inside a describe block lands on Object
  # and leaks into every other spec in the run.
  menus = {
    "Implementation" => "System Security Plans",
    "Assessment"     => "Assessment Plans",
    "Enterprise"     => "Organizations"
  }

  menus.each do |toggle, entry|
    it "opens #{toggle} on click and reveals its entries" do
      resize(1440)
      # click_button matches <button> and <input type=submit> only. An
      # `<a role="button">` fails here, which is the regression this catches.
      click_button toggle

      expect(page).to have_link(entry, visible: true, wait: 3),
        "#{toggle} did not open, or #{entry.inspect} is missing from it"
    end
  end

  # The accessibility claim itself. An anchor never satisfies this: Space
  # scrolls the page instead of activating the control.
  it "opens a menu with the keyboard alone, no mouse" do
    resize(1440)
    toggle = find_button("Assessment")
    toggle.send_keys(:space)

    expect(page).to have_link("Assessment Plans", visible: true, wait: 3),
      "the Assessment toggle did not respond to the Space key — it is not a native button"
  end

  # #1042 — the other half of the breakpoint. Below 1400px the links live behind
  # the hamburger, and the whole point of that change is that they are HIDDEN,
  # not LOST. Without this, the suite above could be satisfied by a navbar that
  # simply deletes its links at laptop widths.
  it "reaches the same menus through the hamburger below the expand breakpoint" do
    resize(1280)

    expect(page).not_to have_button("Implementation", visible: true, wait: 2),
      "at 1280px the bar should be collapsed, so the nav links are behind the toggler"

    find("button.navbar-toggler").click

    expect(page).to have_button("Implementation", visible: true, wait: 3),
      "opening the hamburger must reveal the nav links — hidden is fine, unreachable is not"

    click_button "Implementation"
    expect(page).to have_link("System Security Plans", visible: true, wait: 3),
      "the dropdown must still open once the hamburger has revealed it"
  end

  # The persistent controls are the reason the group sits OUTSIDE the collapse.
  it "keeps Help, the theme toggle and the account menu visible when collapsed" do
    resize(1280)

    expect(page).to have_css("a.sparc-nav-btn[href*='/help']", visible: true),
      "Help must stay one click at every width — #880 built the drawer for mid-task lookups"
    expect(page).to have_css("[data-controller='theme'] button", visible: true),
      "the theme toggle must stay reachable without opening the hamburger"
  end
end
