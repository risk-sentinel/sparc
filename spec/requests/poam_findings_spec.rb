# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PoamFindings", type: :request do
  let(:user) { create(:user) }
  let(:poam) { create(:poam_document, name: "Findings Test POAM") }

  before { sign_in_as(user) }

  describe "POST /poam_documents/:poam_document_id/poam_findings" do
    it "creates a finding with shared OSCAL arrays + audit emission" do
      expect {
        post poam_document_poam_findings_path(poam), params: {
          poam_finding: { title: "AU-2 coverage gap",
                          description: "Audit events missing for new subsystem",
                          implementation_statement_uuid: "stmt-uuid-1",
                          props_data: [ { name: "ctrl", value: "au-2" } ],
                          links_data: [ { href: "https://gov/au2.pdf", rel: "reference" } ] }
        }
      }.to change { poam.poam_findings.count }.by(1)
        .and change { AuditEvent.where(action: "poam_finding_created").count }.by(1)

      finding = poam.poam_findings.last
      expect(finding.title).to eq("AU-2 coverage gap")
      expect(finding.implementation_statement_uuid).to eq("stmt-uuid-1")
      expect(finding.props_data.first).to eq({ "name" => "ctrl", "value" => "au-2" })
    end
  end

  describe "DELETE /poam_documents/:poam_document_id/poam_findings/:id" do
    let!(:finding) { poam.poam_findings.create!(uuid: SecureRandom.uuid, title: "Doomed") }

    it "destroys and writes audit row" do
      expect {
        delete poam_document_poam_finding_path(poam, finding)
      }.to change { poam.poam_findings.count }.by(-1)
        .and change { AuditEvent.where(action: "poam_finding_deleted").count }.by(1)
    end
  end
end
