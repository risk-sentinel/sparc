# frozen_string_literal: true

require "rails_helper"

# #1154 — the new decision fields, filled in and submitted in a real browser
# under the enforced CSP. They are plain form controls with no JavaScript; were
# anything on either form blocked, the submit would not persist and the saved
# values asserted below would not be reached.
RSpec.describe "Recording ATO decision data in the browser", type: :system do
  let(:admin) { create(:user, :admin) }

  before do
    visit "/login"
    accept_consent_banner
    fill_in "Email Address", with: admin.email
    fill_in "Password",      with: "SecurePassword123!"
    click_button "Sign In"
    expect(page).not_to have_field("Email Address", wait: 5)
  end

  it "saves the boundary's authorization and next decision dates" do
    boundary = create(:authorization_boundary, name: "Decision Boundary")

    visit edit_authorization_boundary_path(boundary)
    fill_in "authorization_boundary_authorization_date", with: Date.new(2025, 10, 11)
    fill_in "authorization_boundary_next_decision_date", with: Date.new(2026, 10, 11)
    click_button "Update Authorization boundary"

    expect(page).to have_content("Authorization boundary updated.")
    boundary.reload
    expect(boundary.authorization_date).to eq("2025-10-11")
    expect(boundary.next_decision_date).to eq("2026-10-11")

    # And the form shows what was saved when reopened.
    visit edit_authorization_boundary_path(boundary)
    expect(find_field("authorization_boundary_next_decision_date").value).to eq("2026-10-11")
  end

  it "saves a POA&M risk's blocks-ATO decision, condition expiry and reopen trigger" do
    poam = create(:poam_document, name: "Decision POA&M")
    # `remediating` on purpose: the form's status select used to omit it, so a
    # risk in that state opened with a blank REQUIRED select and the browser
    # refused the submit without a word.
    risk = create(:poam_risk, poam_document: poam, title: "Decision risk", status: "remediating")

    visit edit_poam_document_poam_risk_path(poam, risk)
    select "Yes — blocks the ATO", from: "poam_risk_blocks_ato"
    fill_in "poam_risk_condition_expires", with: Date.new(2026, 11, 1)
    fill_in "poam_risk_reopen_trigger", with: "score<0.85"
    click_button "Update Risk"

    expect(page).to have_content("Risk updated")
    risk.reload
    expect(risk.blocks_ato).to be(true)
    expect(risk.condition_expires).to eq(Date.new(2026, 11, 1))
    expect(risk.reopen_trigger).to eq("score<0.85")
    expect(risk.status).to eq("remediating")

    visit edit_poam_document_poam_risk_path(poam, risk)
    select "No — does not block the ATO", from: "poam_risk_blocks_ato"
    click_button "Update Risk"

    expect(page).to have_content("Risk updated")
    expect(risk.reload.blocks_ato).to be(false)
  end
end
