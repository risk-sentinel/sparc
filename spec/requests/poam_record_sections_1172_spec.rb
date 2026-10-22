# frozen_string_literal: true

require "rails_helper"

# v1.17.2 — the POA&M page reaches every record it holds, and resolving a risk
# or a remediation keeps it.
#
# Before this, risks, remediations, observations, findings and components had
# "+ Add" on the page and no way back to edit or delete them. Risks rendered
# only inside the items they were linked to, so an unlinked risk (257 of 263 on
# the preserved database) never appeared at all.
#
# Close / Reopen (risk) and Mark completed (remediation) are the OSCAL-native
# resolutions (PoamResolutionService). The note is required (owner,
# 2026-10-22) and lands in the risk's OSCAL risk-log, which the export carries.
RSpec.describe "POA&M record sections and resolution (v1.17.2)", type: :request do
  let(:user) { create(:user) }
  let(:poam) { create(:poam_document, name: "Sections POAM") }
  let(:risk_attrs) do
    { title: "Unlinked risk", description: "d", statement: "s", status: "open",
      impact: "high", likelihood: "moderate", deadline: 30.days.from_now.to_date }
  end
  let!(:risk) { poam.poam_risks.create!(risk_attrs.merge(uuid: SecureRandom.uuid)) }
  let!(:remediation) do
    risk.poam_remediations.create!(uuid: SecureRandom.uuid, title: "Patch it", description: "d",
                                   lifecycle: "planned")
  end

  def log_entries(record) = Array(record.reload.risk_log_data["entries"])

  describe "the POA&M page" do
    before do
      grant_document_permission(user, "poam.write", poam)
      grant_document_permission(user, "poam.read", poam)
      sign_in_as(user)
    end

    it "lists an unlinked risk with Edit, Delete and Close" do
      expect(risk.poam_items).to be_empty

      get poam_document_path(poam)

      section = Nokogiri::HTML(response.body).at_css("[data-testid='poam-section-risks']")
      expect(section.text).to include("Risks (1)", "Unlinked risk")
      expect(section.at_css("a[href='#{edit_poam_document_poam_risk_path(poam, risk)}']")).to be_present
      expect(section.at_css("form[action='#{poam_document_poam_risk_path(poam, risk)}']")).to be_present
      expect(section.at_css("form[action='#{close_poam_document_poam_risk_path(poam, risk)}']")).to be_present
    end

    it "gives every kind of record a section with Edit and Delete" do
      observation = poam.poam_observations.create!(uuid: SecureRandom.uuid, title: "An observation",
                                                   description: "d", collected: Time.current)
      finding = poam.poam_findings.create!(uuid: SecureRandom.uuid, title: "A finding", description: "d",
                                           target_data: { "type" => "objective-id", "target-id" => "ac-1",
                                                          "status" => { "state" => "not-satisfied" } })
      component = poam.poam_local_components.create!(uuid: SecureRandom.uuid, title: "A component",
                                                     description: "d", component_type: "software",
                                                     status_state: "operational")

      get poam_document_path(poam)
      doc = Nokogiri::HTML(response.body)

      {
        "remediations" => [ edit_poam_document_poam_remediation_path(poam, remediation),
                            poam_document_poam_remediation_path(poam, remediation) ],
        "observations" => [ edit_poam_document_poam_observation_path(poam, observation),
                            poam_document_poam_observation_path(poam, observation) ],
        "findings" => [ edit_poam_document_poam_finding_path(poam, finding),
                        poam_document_poam_finding_path(poam, finding) ],
        "components" => [ edit_poam_document_poam_local_component_path(poam, component),
                          poam_document_poam_local_component_path(poam, component) ]
      }.each do |key, (edit_path, delete_path)|
        section = doc.at_css("[data-testid='poam-section-#{key}']")
        expect(section).to be_present, "no #{key} section"
        expect(section.at_css("a[href='#{edit_path}']")).to be_present, "#{key}: no Edit"
        expect(section.at_css("form[action='#{delete_path}'] input[name='_method'][value='delete']"))
          .to be_present, "#{key}: no Delete"
      end
    end

    it "warns that deleting a risk takes its remediations, and points at Close" do
      get poam_document_path(poam)

      confirm = Nokogiri::HTML(response.body)
                        .at_css("form[action='#{poam_document_poam_risk_path(poam, risk)}'] [data-turbo-confirm]")
      expect(confirm["data-turbo-confirm"]).to include("1 remediation", "Close it instead")
    end

    it "offers Mark completed on a remediation that is not completed, and not on one that is" do
      get poam_document_path(poam)
      expect(response.body).to include(complete_poam_document_poam_remediation_path(poam, remediation))

      remediation.update!(lifecycle: "completed")
      get poam_document_path(poam)
      expect(response.body).not_to include(complete_poam_document_poam_remediation_path(poam, remediation))
    end
  end

  describe "closing and reopening a risk on the web" do
    before do
      grant_document_permission(user, "poam.write", poam)
      sign_in_as(user)
    end

    it "closes with a note, recording it in the OSCAL risk log and the audit trail" do
      expect {
        patch close_poam_document_poam_risk_path(poam, risk), params: { note: "Patched in release 4.2" }
      }.to change { AuditEvent.where(action: "poam_risk_closed").count }.by(1)

      expect(risk.reload.status).to eq("closed")
      entry = log_entries(risk).sole
      expect(entry).to include("title" => "Closed", "description" => "Patched in release 4.2",
                               "status-change" => "closed")
      expect(entry["uuid"]).to match(/\A[0-9a-f-]{36}\z/)
      expect(Time.iso8601(entry["start"])).to be_within(1.minute).of(Time.current)
    end

    it "refuses to close without a note, and changes nothing" do
      patch close_poam_document_poam_risk_path(poam, risk), params: { note: "  " }

      expect(flash[:error]).to include("a note is required")
      expect(risk.reload.status).to eq("open")
      expect(log_entries(risk)).to be_empty
    end

    it "refuses to close a risk that is already closed" do
      risk.update!(status: "closed")
      patch close_poam_document_poam_risk_path(poam, risk), params: { note: "again" }

      expect(flash[:error]).to include("already closed")
      expect(log_entries(risk)).to be_empty
    end

    it "reopens a closed risk with a note, keeping the closing entry" do
      patch close_poam_document_poam_risk_path(poam, risk), params: { note: "Fixed" }
      patch reopen_poam_document_poam_risk_path(poam, risk), params: { note: "Regressed in 4.3" }

      expect(risk.reload.status).to eq("open")
      expect(log_entries(risk).map { |e| e["status-change"] }).to eq(%w[closed open])
    end

    it "refuses to reopen a risk that is not closed" do
      patch reopen_poam_document_poam_risk_path(poam, risk), params: { note: "why" }

      expect(flash[:error]).to include("Only a closed risk can be reopened")
      expect(risk.reload.status).to eq("open")
    end

    it "exports the closure: status closed and the risk-log entry, schema-valid at the risk" do
      patch close_poam_document_poam_risk_path(poam, risk), params: { note: "Patched" }

      json = JSON.parse(OscalPoamExportService.new(poam).export_unvalidated)
      exported = json.dig("plan-of-action-and-milestones", "risks").find { |r| r["uuid"] == risk.uuid }
      expect(exported["status"]).to eq("closed")
      expect(exported.dig("risk-log", "entries").sole).to include("status-change" => "closed",
                                                                  "description" => "Patched")

      risk_errors = OscalSchemaValidationService.validate(:poam, json).errors
                                                .select { |e| e.to_s.include?("/risks") }
      expect(risk_errors).to be_empty
    end
  end

  describe "marking a remediation completed on the web" do
    before do
      grant_document_permission(user, "poam.write", poam)
      sign_in_as(user)
    end

    it "sets the OSCAL lifecycle to completed and audits it" do
      expect {
        patch complete_poam_document_poam_remediation_path(poam, remediation)
      }.to change { AuditEvent.where(action: "poam_remediation_completed").count }.by(1)

      expect(remediation.reload.lifecycle).to eq("completed")
    end

    it "refuses one that is already completed" do
      remediation.update!(lifecycle: "completed")
      patch complete_poam_document_poam_remediation_path(poam, remediation)

      expect(flash[:error]).to include("already completed")
    end
  end

  describe "without poam.write" do
    before do
      grant_document_permission(user, "poam.read", poam)
      sign_in_as(user)
    end

    it "cannot close a risk" do
      patch close_poam_document_poam_risk_path(poam, risk), params: { note: "sneaky" }

      expect(risk.reload.status).to eq("open")
      expect(log_entries(risk)).to be_empty
    end

    it "cannot reopen a risk" do
      risk.update!(status: "closed")
      patch reopen_poam_document_poam_risk_path(poam, risk), params: { note: "sneaky" }

      expect(risk.reload.status).to eq("closed")
    end

    it "cannot mark a remediation completed" do
      patch complete_poam_document_poam_remediation_path(poam, remediation)

      expect(remediation.reload.lifecycle).to eq("planned")
    end
  end

  describe "through the API" do
    let(:writer) { create(:user).tap { |u| grant_document_permission(u, "poam.write", poam) } }
    let(:reader) { create(:user).tap { |u| grant_document_permission(u, "poam.read", poam) } }

    def headers_for(owner)
      { "Authorization" => "Bearer #{ApiToken.generate!(user: owner, name: "t").plaintext_token}" }
    end

    it "closes and reopens a risk, with the risk log in the response" do
      post "/api/v1/poam_risks/#{risk.id}/close", params: { note: "Patched" },
                                                   headers: headers_for(writer), as: :json
      expect(response).to have_http_status(:ok)
      body = response.parsed_body["data"]
      expect(body["status"]).to eq("closed")
      expect(body.dig("risk_log", "entries").sole["status-change"]).to eq("closed")

      post "/api/v1/poam_risks/#{risk.id}/reopen", params: { note: "Back" },
                                                    headers: headers_for(writer), as: :json
      expect(response).to have_http_status(:ok)
      expect(risk.reload.status).to eq("open")
    end

    it "is a 422 naming the note when it is missing or blank, and nothing changes" do
      [ {}, { note: " " } ].each do |body|
        post "/api/v1/poam_risks/#{risk.id}/close", params: body, headers: headers_for(writer), as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("a note is required")
      end
      expect(risk.reload.status).to eq("open")
    end

    it "forbids a caller without poam.write" do
      post "/api/v1/poam_risks/#{risk.id}/close", params: { note: "x" }, headers: headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/poam_documents/#{poam.slug}/remediations/#{remediation.id}/complete",
           headers: headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)

      expect(risk.reload.status).to eq("open")
      expect(remediation.reload.lifecycle).to eq("planned")
    end

    it "marks a remediation completed, and refuses it a second time" do
      path = "/api/v1/poam_documents/#{poam.slug}/remediations/#{remediation.id}/complete"
      post path, headers: headers_for(writer), as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "lifecycle")).to eq("completed")

      post path, headers: headers_for(writer), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
