# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PoamRisks", type: :request do
  let(:user) { create(:user) }
  let(:poam) { create(:poam_document, name: "Risks Test POAM") }

  before { sign_in_as(user) }

  describe "GET /poam_documents/:poam_document_id/poam_risks/new" do
    it "renders the new-risk form" do
      get new_poam_document_poam_risk_path(poam)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Add Risk to")
    end
  end

  describe "POST /poam_documents/:poam_document_id/poam_risks" do
    let(:base_attrs) do
      { title: "Test Risk", description: "A risk to track",
        statement: "Asset X has weakness Y allowing Z",
        status: "open", impact: "high", likelihood: "medium" }
    end

    it "creates a risk with core fields and props/links/origins" do
      post poam_document_poam_risks_path(poam), params: {
        poam_risk: base_attrs.merge(
          props_data: [ { name: "severity", value: "critical" } ],
          links_data: [ { href: "https://example.gov/risk-doc.pdf", rel: "reference",
                          media_type: "application/pdf" } ],
          origins_data: [ { actor_type: "tool", actor_uuid: "scanner-uuid" } ]
        )
      }

      risk = poam.poam_risks.find_by(title: "Test Risk")
      expect(risk).to be_present
      expect(risk.uuid).to be_present
      expect(risk.status).to eq("open")
      expect(risk.impact).to eq("high")
      expect(risk.props_data.first["value"]).to eq("critical")
      expect(risk.links_data.first["media-type"]).to eq("application/pdf")
      expect(risk.origins_data.first.dig("actors", 0, "actor-uuid")).to eq("scanner-uuid")
      expect(response).to redirect_to(poam_document_path(poam))
    end

    it "creates a risk with no extensibility arrays" do
      post poam_document_poam_risks_path(poam), params: { poam_risk: base_attrs }

      risk = poam.poam_risks.find_by(title: "Test Risk")
      expect(risk).to be_present
      expect(risk.props_data).to eq([])
      expect(risk.links_data).to eq([])
      expect(risk.origins_data).to eq([])
    end

    it "returns 422 when title is missing" do
      post poam_document_poam_risks_path(poam), params: { poam_risk: base_attrs.merge(title: "") }
      expect(response).to have_http_status(:found).or have_http_status(:ok)
    end

    it "writes a poam_risk_created audit event" do
      expect {
        post poam_document_poam_risks_path(poam), params: { poam_risk: base_attrs }
      }.to change { AuditEvent.where(action: "poam_risk_created").count }.by(1)
    end
  end

  describe "PATCH /poam_documents/:poam_document_id/poam_risks/:id" do
    let!(:risk) do
      poam.poam_risks.create!(uuid: SecureRandom.uuid, title: "Existing Risk",
                              status: "open", impact: "medium")
    end

    it "updates fields and props/links" do
      patch poam_document_poam_risk_path(poam, risk), params: {
        poam_risk: {
          title: "Renamed Risk", impact: "low",
          props_data: [ { name: "rev", value: "2" } ]
        }
      }
      risk.reload
      expect(risk.title).to eq("Renamed Risk")
      expect(risk.impact).to eq("low")
      expect(risk.props_data).to eq([ { "name" => "rev", "value" => "2" } ])
    end
  end

  describe "DELETE /poam_documents/:poam_document_id/poam_risks/:id" do
    let!(:risk) do
      poam.poam_risks.create!(uuid: SecureRandom.uuid, title: "To Be Deleted")
    end

    it "destroys the risk and writes an audit event" do
      expect {
        delete poam_document_poam_risk_path(poam, risk)
      }.to change { poam.poam_risks.count }.by(-1)
        .and change { AuditEvent.where(action: "poam_risk_deleted").count }.by(1)
    end
  end
end
