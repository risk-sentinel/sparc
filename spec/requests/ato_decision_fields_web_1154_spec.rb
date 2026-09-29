# frozen_string_literal: true

require "rails_helper"

# #1154 — the web edit forms write the same decision data the API does: the
# boundary's two dates and a POA&M risk's three decision fields.
RSpec.describe "ATO decision fields through the web forms (#1154)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "authorization boundary edit form" do
    let(:admin) { create(:user, :admin) }
    let(:boundary) do
      create(:authorization_boundary).tap do |b|
        b.update!(boundary_metadata: { "system_owner" => { "name" => "Kept" } })
      end
    end

    it "renders both date fields" do
      sign_in_as(admin)
      get edit_authorization_boundary_path(boundary)

      expect(response.body).to include('name="authorization_boundary[authorization_date]"')
      expect(response.body).to include('name="authorization_boundary[next_decision_date]"')
    end

    it "saves both dates WITHOUT discarding the rest of boundary_metadata" do
      sign_in_as(admin)
      patch authorization_boundary_path(boundary), params: {
        authorization_boundary: { name: boundary.name, authorization_date: "2025-10-11", next_decision_date: "2026-10-11" }
      }

      expect(response).to redirect_to(authorization_boundary_path(boundary.reload))
      expect(boundary.next_decision_date).to eq("2026-10-11")
      expect(boundary.authorization_date).to eq("2025-10-11")
      expect(boundary.boundary_metadata["system_owner"]).to eq({ "name" => "Kept" })
    end

    it "re-renders with the error for a malformed date and stores nothing" do
      sign_in_as(admin)
      patch authorization_boundary_path(boundary), params: {
        authorization_boundary: { next_decision_date: "next spring" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(boundary.reload.next_decision_date).to be_nil
    end

    it "does not let an anonymous request write them" do
      patch authorization_boundary_path(boundary), params: { authorization_boundary: { next_decision_date: "2026-10-11" } }

      expect(response).to have_http_status(:redirect)
      expect(boundary.reload.next_decision_date).to be_nil
    end
  end

  describe "POA&M risk edit form" do
    let(:user) { create(:user) }
    let(:poam) { create(:poam_document) }
    let(:risk) { create(:poam_risk, poam_document: poam) }
    let(:decision) { { blocks_ato: "true", condition_expires: "2026-11-01", reopen_trigger: "blockers>=1" } }

    it "renders the three decision fields" do
      grant_document_permission(user, "poam.write", poam)
      sign_in_as(user)
      get edit_poam_document_poam_risk_path(poam, risk)

      expect(response.body).to include('name="poam_risk[blocks_ato]"')
      expect(response.body).to include('name="poam_risk[condition_expires]"')
      expect(response.body).to include('name="poam_risk[reopen_trigger]"')
    end

    it "saves them for a user holding poam.write" do
      grant_document_permission(user, "poam.write", poam)
      sign_in_as(user)
      patch poam_document_poam_risk_path(poam, risk), params: { poam_risk: decision }

      expect(response).to redirect_to(poam_document_path(poam))
      risk.reload
      expect([ risk.blocks_ato, risk.condition_expires, risk.reopen_trigger ])
        .to eq([ true, Date.new(2026, 11, 1), "blockers>=1" ])
    end

    it "keeps an undecided risk undecided when the select is left blank" do
      grant_document_permission(user, "poam.write", poam)
      sign_in_as(user)
      patch poam_document_poam_risk_path(poam, risk), params: { poam_risk: { blocks_ato: "", reopen_trigger: "" } }

      expect(risk.reload.blocks_ato).to be_nil
      expect(risk.reopen_trigger).to be_nil
    end

    it "refuses a user without poam.write" do
      sign_in_as(user)
      patch poam_document_poam_risk_path(poam, risk), params: { poam_risk: decision }

      expect(risk.reload.blocks_ato).to be_nil
    end
  end
end
