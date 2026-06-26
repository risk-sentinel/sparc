# frozen_string_literal: true

require "rails_helper"

# Layer 1, regression spec #3 — Service Account admin checkbox
# (#535 / #536-class regression).
#
# Catches:
#   - The "Grant admin privileges" checkbox disappearing from the
#     New SA form (#535-style render regression)
#   - The form-submit path silently dropping the admin flag so the
#     created SA isn't actually admin even when the checkbox was
#     checked (#536-style validation drop)
#   - Any future change to the SA admin gating that breaks the
#     creation flow end-to-end
RSpec.describe "Admin: create a service account", type: :system do
  let(:admin) { create(:user, :admin) }

  before do
    # System specs: env vars, not RSpec mocks (thread-local doesn't
    # reach Capybara's Puma thread). support/system_spec_config.rb
    # sets SPARC_ENABLE_LOCAL_LOGIN=true by default.
    visit "/login"
    accept_consent_banner
    fill_in "Email Address", with: admin.email
    fill_in "Password",      with: "SecurePassword123!"
    click_button "Sign In"

    # Hard-wait for the redirect so the next visit carries the
    # session cookie.
    expect(page).not_to have_field("Email Address", wait: 5),
      "Sign-in failed. Path=#{page.current_path}; body excerpt: #{page.body[0, 500]}"
  end

  it "renders the 'Grant admin privileges' checkbox on the New SA form" do
    visit "/admin/service_accounts/new"
    expect(page).to have_content("New Service Account")
    expect(page).to have_field("Grant admin privileges", type: "checkbox")
  end

  it "creates an admin service account when the checkbox is checked" do
    visit "/admin/service_accounts/new"

    sa_email = "spec-sa-#{SecureRandom.hex(4)}@service.local"
    fill_in "Name",  with: "Spec SA"
    fill_in "Email", with: sa_email
    # Owner dropdown shows the user's display_name (not email).
    select admin.display_name, from: "Owner"
    check  "Grant admin privileges"

    click_button "Create Service Account & Generate Token"

    # Wait for the redirect to the show page (proof the form-POST
    # committed). Without this we race the server-thread commit and
    # see no row.
    expect(page).to have_content("API Token", wait: 5)

    sa = User.find_by(email: sa_email)
    sa ||= User.where("LOWER(email) = ?", sa_email.downcase).first
    expect(sa).to be_present, "SA not created — sa_email=#{sa_email.inspect}, recent users: #{User.order(created_at: :desc).limit(3).pluck(:email).inspect}"
    expect(sa).to be_service_account
    expect(sa).to be_admin
  end
end
