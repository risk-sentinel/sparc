# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PoamObservations", type: :request do
  let(:user) { create(:user) }
  let(:poam) { create(:poam_document, name: "Observations Test POAM") }

  before { sign_in_as(user) }

  describe "POST /poam_documents/:poam_document_id/poam_observations" do
    let(:base_attrs) do
      { title: "Outdated TLS",
        description: "Edge nodes still negotiating TLS 1.0",
        collected: "2026-04-01T12:00:00Z" }
    end

    it "creates an observation with shared OSCAL arrays + audit emission" do
      expect {
        post poam_document_poam_observations_path(poam), params: {
          poam_observation: base_attrs.merge(
            props_data: [ { name: "scanner", value: "nmap" } ],
            origins_data: [ { actor_type: "tool", actor_uuid: "scanner-uuid" } ]
          )
        }
      }.to change { poam.poam_observations.count }.by(1)
        .and change { AuditEvent.where(action: "poam_observation_created").count }.by(1)

      obs = poam.poam_observations.last
      expect(obs.title).to eq("Outdated TLS")
      expect(obs.uuid).to be_present
      expect(obs.collected).to be_within(1.second).of(Time.parse("2026-04-01T12:00:00Z"))
      expect(obs.props_data.first).to eq({ "name" => "scanner", "value" => "nmap" })
      expect(obs.origins_data.first.dig("actors", 0, "actor-uuid")).to eq("scanner-uuid")
    end
  end

  describe "PATCH /poam_documents/:poam_document_id/poam_observations/:id" do
    let!(:obs) { poam.poam_observations.create!(uuid: SecureRandom.uuid, title: "Original") }

    it "updates fields and writes audit" do
      patch poam_document_poam_observation_path(poam, obs),
            params: { poam_observation: { title: "Updated" } }
      expect(obs.reload.title).to eq("Updated")
    end
  end

  describe "POST with methods_data (#424)" do
    it "stores OSCAL-allowed methods in the JSONB column" do
      post poam_document_poam_observations_path(poam), params: {
        poam_observation: { title: "Methods Test",
                            description: "—",
                            methods_data: [ "EXAMINE", "TEST" ] }
      }

      obs = poam.poam_observations.find_by(title: "Methods Test")
      expect(obs.methods_data).to eq([ "EXAMINE", "TEST" ])
    end

    it "rejects unknown method values silently" do
      post poam_document_poam_observations_path(poam), params: {
        poam_observation: { title: "Methods Filter Test",
                            description: "—",
                            methods_data: [ "EXAMINE", "DARK_MAGIC", "" ] }
      }

      obs = poam.poam_observations.find_by(title: "Methods Filter Test")
      expect(obs.methods_data).to eq([ "EXAMINE" ])
    end
  end

  describe "DELETE /poam_documents/:poam_document_id/poam_observations/:id" do
    let!(:obs) { poam.poam_observations.create!(uuid: SecureRandom.uuid, title: "Doomed") }

    it "destroys and audits" do
      expect {
        delete poam_document_poam_observation_path(poam, obs)
      }.to change { poam.poam_observations.count }.by(-1)
        .and change { AuditEvent.where(action: "poam_observation_deleted").count }.by(1)
    end
  end
end
