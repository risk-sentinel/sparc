# frozen_string_literal: true

require "rails_helper"

# #1341 — the login consent banner (#190, AC-8) in a real browser: getting
# around it never reveals the login form or a signed-in page. Only Proceed
# reveals the form, and only signing in reaches a signed-in page.
#
# The banner is forced on for every system spec (spec/support/system_spec_config.rb).
# Signing in still needs valid credentials on the server; the banner is the
# notice in front of it.
RSpec.describe "Login consent banner (#1341)", type: :system do
  let(:admin) { create(:user, :admin, password: "SecurePassword123!", password_confirmation: "SecurePassword123!") }

  let(:modal) { "[data-consent-banner-target='modal']" }
  let(:login_card) { "[data-consent-banner-target='loginCard']" }

  def modal_open? = page.evaluate_script("document.querySelector(\"#{modal}\").classList.contains('show')")
  def wait_for_modal = wait_for_consent_modal_settled

  before { visit "/login" }

  it "hides the login form until consent, and Escape or a click outside does not dismiss it" do
    wait_for_modal
    expect(page).to have_css("#{login_card}.d-none", visible: :all)
    expect(page).to have_no_field("email")

    # Escape, pressed as a user presses it: a real key to whatever holds focus
    # (Bootstrap moves focus into the modal when it opens).
    page.driver.browser.action.send_keys(:escape).perform
    sleep 0.6 # longer than Bootstrap's hide transition: a dismissal would have finished
    expect(modal_open?).to be(true), "Escape dismissed the consent banner"

    # A click on the backdrop: the viewport's top-left corner, outside the
    # centred dialog. (Capybara's element offsets count from the centre.)
    page.driver.browser.action.move_to_location(5, 5).click.perform
    sleep 0.6
    expect(modal_open?).to be(true), "a click outside the dialog dismissed the consent banner"

    expect(page).to have_css("#{login_card}.d-none", visible: :all)
    expect(page).to have_no_field("email")
  end

  it "keeps the login form hidden on Cancel, and says why" do
    wait_for_modal
    click_button "Cancel"

    expect(page).to have_content("Cannot login without consent")
    expect(page).to have_css("#{login_card}.d-none", visible: :all)
    expect(page).to have_no_field("email")
  end

  it "still sends a signed-in page to sign-in after Cancel" do
    wait_for_modal
    click_button "Cancel"
    visit "/ssp_documents"

    expect(page).to have_current_path("/login")
    expect(page).to have_no_field("email")
  end

  it "reveals the form on Proceed, and only signing in reaches a signed-in page" do
    accept_consent_banner
    expect(page).to have_field("email")

    visit "/ssp_documents"
    expect(page).to have_current_path("/login")

    accept_consent_banner
    fill_in "Email Address", with: admin.email
    fill_in "Password", with: "SecurePassword123!"
    click_button "Sign In"
    expect(page).to have_no_field("email", wait: 5)

    visit "/ssp_documents"
    expect(page).to have_current_path("/ssp_documents")
  end
end
