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
    toggle = find_button("Assessment")
    toggle.send_keys(:space)

    expect(page).to have_link("Assessment Plans", visible: true, wait: 3),
      "the Assessment toggle did not respond to the Space key — it is not a native button"
  end
end
