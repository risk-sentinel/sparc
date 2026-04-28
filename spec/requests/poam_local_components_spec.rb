# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PoamLocalComponents", type: :request do
  let(:user) { create(:user) }
  let(:poam) { create(:poam_document, name: "Components Test POAM") }

  before { sign_in_as(user) }

  describe "POST /poam_documents/:poam_document_id/poam_local_components" do
    it "creates a component with shared OSCAL props/links + audit emission" do
      expect {
        post poam_document_poam_local_components_path(poam), params: {
          poam_local_component: { title: "Customer-facing API",
                                  component_type: "service",
                                  description: "Public-facing REST API",
                                  status_state: "operational",
                                  props_data: [ { name: "asset-id", value: "API-001" } ],
                                  links_data: [ { href: "https://gov/api-spec.html",
                                                  rel: "depends-on",
                                                  media_type: "text/html" } ] }
        }
      }.to change { poam.poam_local_components.count }.by(1)
        .and change { AuditEvent.where(action: "poam_local_component_created").count }.by(1)

      comp = poam.poam_local_components.last
      expect(comp.title).to eq("Customer-facing API")
      expect(comp.component_type).to eq("service")
      expect(comp.status_state).to eq("operational")
      expect(comp.links_data.first["media-type"]).to eq("text/html")
    end
  end

  describe "DELETE /poam_documents/:poam_document_id/poam_local_components/:id" do
    let!(:comp) do
      poam.poam_local_components.create!(uuid: SecureRandom.uuid, title: "Doomed",
                                          component_type: "service")
    end

    it "destroys and audits" do
      expect {
        delete poam_document_poam_local_component_path(poam, comp)
      }.to change { poam.poam_local_components.count }.by(-1)
        .and change { AuditEvent.where(action: "poam_local_component_deleted").count }.by(1)
    end
  end
end
