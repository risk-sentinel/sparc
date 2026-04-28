# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PoamRemediations + PoamMilestones", type: :request do
  let(:user) { create(:user) }
  let(:poam) { create(:poam_document, name: "Remediations Test POAM") }
  let!(:risk) { poam.poam_risks.create!(uuid: SecureRandom.uuid, title: "Parent Risk") }

  before { sign_in_as(user) }

  describe "Remediations CRUD" do
    let(:base_attrs) do
      { poam_risk_id: risk.id, title: "Patch Library X",
        description: "Upgrade to v2.5", lifecycle: "planned" }
    end

    it "renders the new form" do
      get new_poam_document_poam_remediation_path(poam)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Add Remediation to")
    end

    it "creates a remediation under a chosen risk and writes audit row" do
      expect {
        post poam_document_poam_remediations_path(poam),
             params: { poam_remediation: base_attrs.merge(
               props_data: [ { name: "phase", value: "rollout" } ],
               links_data: [ { href: "https://x.gov/rollout-plan.pdf", rel: "reference" } ]
             ) }
      }.to change { risk.poam_remediations.count }.by(1)
        .and change { AuditEvent.where(action: "poam_remediation_created").count }.by(1)

      remediation = risk.poam_remediations.last
      expect(remediation.title).to eq("Patch Library X")
      expect(remediation.uuid).to be_present
      expect(remediation.props_data.first["value"]).to eq("rollout")
    end

    it "updates and destroys a remediation" do
      remediation = risk.poam_remediations.create!(uuid: SecureRandom.uuid, title: "Old")

      patch poam_document_poam_remediation_path(poam, remediation),
            params: { poam_remediation: base_attrs.merge(title: "Renamed") }
      expect(remediation.reload.title).to eq("Renamed")

      expect {
        delete poam_document_poam_remediation_path(poam, remediation)
      }.to change { risk.poam_remediations.count }.by(-1)
        .and change { AuditEvent.where(action: "poam_remediation_deleted").count }.by(1)
    end
  end

  describe "Milestones CRUD" do
    let!(:remediation) { risk.poam_remediations.create!(uuid: SecureRandom.uuid, title: "Patch") }

    it "creates a milestone under a remediation with props/links" do
      expect {
        post poam_document_poam_remediation_poam_milestones_path(poam, remediation),
             params: { poam_milestone: { title: "Staging deploy",
                                          description: "Patch live in staging",
                                          due_date: "2026-06-01",
                                          milestone_type: "task",
                                          props_data: [ { name: "owner", value: "platform-team" } ],
                                          links_data: [ { href: "https://ci.example.gov/build/123" } ] } }
      }.to change { remediation.poam_milestones.count }.by(1)
        .and change { AuditEvent.where(action: "poam_milestone_created").count }.by(1)

      milestone = remediation.poam_milestones.last
      expect(milestone.title).to eq("Staging deploy")
      expect(milestone.due_date.to_s).to eq("2026-06-01")
      expect(milestone.props_data.first["name"]).to eq("owner")
    end

    it "updates and destroys a milestone" do
      milestone = remediation.poam_milestones.create!(uuid: SecureRandom.uuid, title: "M")

      patch poam_document_poam_remediation_poam_milestone_path(poam, remediation, milestone),
            params: { poam_milestone: { title: "Updated" } }
      expect(milestone.reload.title).to eq("Updated")

      expect {
        delete poam_document_poam_remediation_poam_milestone_path(poam, remediation, milestone)
      }.to change { remediation.poam_milestones.count }.by(-1)
    end
  end
end
