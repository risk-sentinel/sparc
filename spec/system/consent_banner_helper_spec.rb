# frozen_string_literal: true

require "rails_helper"

# `accept_consent_banner` decides from the configuration, not from the screen
# (spec/support/system_spec_config.rb). Every other system spec runs with the
# banner on and not yet accepted, so the other two paths are proved here.
RSpec.describe "accept_consent_banner", type: :system do
  it "with the banner on, accepts it and reveals the login form" do
    visit "/login"
    accept_consent_banner

    expect(page).to have_field("email")
  end

  it "with consent already given this session, finds the login form revealed" do
    visit "/login"
    accept_consent_banner
    visit "/login"

    expect(page).to have_no_button("Proceed")
    accept_consent_banner
    expect(page).to have_field("email")
  end

  it "with the banner off, signs straight in to the login form" do
    ENV["SPARC_BANNER"] = ""
    visit "/login"

    accept_consent_banner
    expect(page).to have_no_button("Proceed")
    expect(page).to have_field("email")
  end
end
