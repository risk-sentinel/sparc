# frozen_string_literal: true

require "rails_helper"

# v1.17.2 — the last OSCAL risk fields the web forms could not author, which
# the API has accepted since #1092:
#
#   * the SAR risk card gains `deadline` and `remediations`;
#   * the POA&M risk form gains `threat-ids` and `mitigating-factors`, through
#     the same section and the same normaliser as the SAR card
#     (RiskCollectionParams#normalise_form_risk_collections).
#
# Two defects found on the way, pinned here:
#   * saving the form stripped every key it does not edit (props, links,
#     origins, required-assets) from an imported entry;
#   * the SAR enrich save looked risks and findings up by bare id, so anyone
#     who may edit one SAR could overwrite a risk or finding in another. (AC-3)
RSpec.describe "Risk form collections (v1.17.2)", type: :request do
  describe "SAR risk card" do
    let(:user)     { create(:user, :admin) }
    let(:document) { create(:sar_document, name: "Risk Card SAR") }
    let!(:result)  { create(:sar_result, sar_document: document) }
    let!(:risk) do
      result.sar_risks.create!(uuid: SecureRandom.uuid, title: "TLS downgrade",
                               description: "d", statement: "s", status: "open")
    end

    before { sign_in_as(user) }

    def submit(extra = {})
      patch update_enrich_sar_document_path(document), params: { sar_document: { risks: [
        { id: risk.id, sar_result_id: risk.sar_result_id, title: risk.title,
          description: risk.description, statement: risk.statement,
          status: risk.status, collections_present: "1" }.merge(extra)
      ] } }
    end

    it "renders the deadline and remediation editors, for existing risks and the add-risk template" do
      get enrich_sar_document_path(document)

      expect(response.body.scan("sar_document[risks][][deadline]").size).to eq(2)
      expect(response.body.scan("sar_document[risks][][remediations_data][][title]").size).to be >= 2
      expect(response.body).to include("sar_document[risks][][remediations_data][][lifecycle]")
    end

    it "saves a deadline, and clears it when the field is emptied" do
      submit(deadline: "2026-12-31")
      expect(risk.reload.deadline.to_date).to eq(Date.new(2026, 12, 31))

      submit(deadline: "")
      expect(risk.reload.deadline).to be_nil
    end

    it "saves a remediation typed into the card, with a minted uuid" do
      submit(remediations_data: [ { title: "Enforce TLS 1.2", description: "Disable 1.0 and 1.1",
                                    lifecycle: "planned" } ])

      response_entry = risk.reload.remediations_data.sole
      expect(response_entry).to include("title" => "Enforce TLS 1.2", "description" => "Disable 1.0 and 1.1",
                                        "lifecycle" => "planned")
      expect(response_entry["uuid"]).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "keeps an imported remediation's uuid and the content the form does not edit" do
      uuid = SecureRandom.uuid
      risk.update!(remediations_data: [ {
        "uuid" => uuid, "lifecycle" => "recommendation", "title" => "Old", "description" => "Old d",
        "props" => [ { "name" => "type", "value" => "mitigate" } ],
        "required-assets" => [ { "uuid" => SecureRandom.uuid, "description" => "A proxy" } ]
      } ])

      submit(remediations_data: [ { uuid: uuid, title: "New", description: "New d", lifecycle: "completed" } ])

      entry = risk.reload.remediations_data.sole
      expect(entry).to include("uuid" => uuid, "title" => "New", "description" => "New d", "lifecycle" => "completed")
      expect(entry["props"]).to eq([ { "name" => "type", "value" => "mitigate" } ])
      expect(entry["required-assets"].sole["description"]).to eq("A proxy")
    end

    it "keeps an imported mitigating factor's props and links when the card is saved" do
      uuid = SecureRandom.uuid
      risk.update!(mitigating_factors_data: [ {
        "uuid" => uuid, "description" => "Proxy", "implementation-uuid" => "impl-1",
        "links" => [ { "href" => "#ref" } ]
      } ])

      submit(mitigating_factors_data: [ { uuid: uuid, description: "Proxy, allowlisted" } ])

      factor = risk.reload.mitigating_factors_data.sole
      expect(factor).to include("description" => "Proxy, allowlisted", "implementation-uuid" => "impl-1")
      expect(factor["links"]).to eq([ { "href" => "#ref" } ])
    end

    it "refuses a remediation with a title but no description, and saves nothing" do
      submit(title: "Renamed", remediations_data: [ { title: "Half", description: "", lifecycle: "planned" } ])

      expect(flash[:error]).to include("A remediation needs both a title and a description")
      expect(risk.reload.title).to eq("TLS downgrade")
      expect(risk.remediations_data).to eq([])
    end

    # OSCAL types a threat-id's `id` as a URI; `T1078` exports schema-invalid.
    # The #1092 hint suggested exactly that.
    it "refuses a threat ID that is not a URI, and saves nothing" do
      submit(title: "Renamed", threat_ids_data: [ { system: "https://attack.mitre.org", id: "T1078" } ])

      expect(flash[:error]).to include("A threat ID needs its system and its ID as full URIs", "T1078")
      expect(risk.reload.title).to eq("TLS downgrade")
      expect(risk.threat_ids_data).to eq([])
    end

    it "clears remediations when every row is removed" do
      risk.update!(remediations_data: [ { "uuid" => SecureRandom.uuid, "lifecycle" => "planned",
                                          "title" => "t", "description" => "d" } ])

      submit # the marker, and no remediations_data key

      expect(risk.reload.remediations_data).to eq([])
    end

    # What the card writes must export as OSCAL a schema accepts: response
    # needs uuid, lifecycle, title and description; deadline is a date-time.
    it "exports what the card saved, schema-valid at the risk" do
      submit(deadline: "2026-12-31",
             threat_ids_data: [ { system: "https://attack.mitre.org", id: "https://attack.mitre.org/techniques/T1078" } ],
             mitigating_factors_data: [ { description: "MFA" } ],
             remediations_data: [ { title: "Patch", description: "Apply vendor fix", lifecycle: "planned" } ])

      json = JSON.parse(OscalSarExportService.new(document).export_unvalidated)
      exported = json.dig("assessment-results", "results").flat_map { |r| Array(r["risks"]) }.sole
      expect(exported["deadline"]).to start_with("2026-12-31")
      expect(exported["remediations"].sole).to include("title" => "Patch", "lifecycle" => "planned")

      risk_errors = OscalSchemaValidationService.validate(:assessment_results, json).errors
                                                .select { |e| e.to_s.include?("/risks") }
      expect(risk_errors).to be_empty
    end

    it "gives a new risk its deadline and remediations" do
      patch update_enrich_sar_document_path(document), params: { sar_document: { risks: [
        { title: "Fresh", status: "open", deadline: "2027-01-15", collections_present: "1",
          remediations_data: [ { title: "Patch", description: "Apply vendor fix", lifecycle: "planned" } ] }
      ] } }

      fresh = result.sar_risks.find_by!(title: "Fresh")
      expect(fresh.deadline.to_date).to eq(Date.new(2027, 1, 15))
      expect(fresh.remediations_data.sole["title"]).to eq("Patch")
    end
  end

  describe "SAR enrich writes stay inside the SAR being edited" do
    let(:editor) { create(:user) }
    let(:own)    { create(:sar_document, name: "Own SAR") }
    let(:other)  { create(:sar_document, name: "Other SAR", authorization_boundary: create(:authorization_boundary)) }
    let!(:own_result)   { create(:sar_result, sar_document: own) }
    let!(:other_result) { create(:sar_result, sar_document: other) }
    let!(:other_risk) do
      other_result.sar_risks.create!(uuid: SecureRandom.uuid, title: "Not yours",
                                     description: "d", statement: "s", status: "open")
    end
    let!(:other_finding) do
      other_result.sar_findings.create!(uuid: SecureRandom.uuid, title: "Not yours either", description: "d",
                                        target_data: { "type" => "objective-id", "target-id" => "ac-1",
                                                       "status" => { "state" => "satisfied" } })
    end

    before do
      grant_document_permission(editor, "sar.write", own)
      sign_in_as(editor)
    end

    it "does not touch another SAR's risk named by id" do
      patch update_enrich_sar_document_path(own), params: { sar_document: { risks: [
        { id: other_risk.id, title: "Overwritten", description: "x", statement: "x", status: "closed" }
      ] } }

      expect(other_risk.reload.title).to eq("Not yours")
      expect(other_risk.status).to eq("open")
    end

    it "does not touch another SAR's finding named by id" do
      patch update_enrich_sar_document_path(own), params: { sar_document: { findings: [
        { id: other_finding.id, title: "Overwritten", description: "x" }
      ] } }

      expect(other_finding.reload.title).to eq("Not yours either")
    end

    it "still updates a risk in the SAR being edited" do
      mine = own_result.sar_risks.create!(uuid: SecureRandom.uuid, title: "Mine",
                                          description: "d", statement: "s", status: "open")

      patch update_enrich_sar_document_path(own), params: { sar_document: { risks: [
        { id: mine.id, title: "Mine, edited", description: "d", statement: "s", status: "open" }
      ] } }

      expect(mine.reload.title).to eq("Mine, edited")
    end
  end

  describe "POA&M risk form" do
    let(:user) { create(:user) }
    let(:poam) { create(:poam_document, name: "Collections POAM") }
    let(:base_attrs) do
      { title: "Risk", description: "d", statement: "s", status: "open",
        impact: "high", likelihood: "moderate", deadline: 30.days.from_now.to_date }
    end

    before do
      grant_document_permission(user, "poam.write", poam)
      sign_in_as(user)
    end

    it "renders the threat ID and mitigating factor editors, without remediations" do
      get new_poam_document_poam_risk_path(poam)

      expect(response.body).to include("poam_risk[threat_ids_data][][id]")
      expect(response.body).to include("poam_risk[mitigating_factors_data][][description]")
      expect(response.body).to include("poam_risk[collections_present]")
      expect(response.body).not_to include("poam_risk[remediations_data]")
    end

    it "keeps what was typed when a new risk's threat ID is refused" do
      post poam_document_poam_risks_path(poam), params: { poam_risk: base_attrs.merge(
        title: "Typed title", collections_present: "1",
        threat_ids_data: [ { system: "https://attack.mitre.org", id: "T1078" } ]
      ) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Typed title", "A threat ID needs its system and its ID as full URIs")
      expect(poam.poam_risks.where(title: "Typed title")).to be_empty
    end

    it "creates a risk with threat IDs and mitigating factors" do
      post poam_document_poam_risks_path(poam), params: { poam_risk: base_attrs.merge(
        collections_present: "1",
        threat_ids_data: [ { system: "https://attack.mitre.org", id: "https://attack.mitre.org/techniques/T1078" } ],
        mitigating_factors_data: [ { description: "MFA on every account" } ]
      ) }

      risk = poam.poam_risks.find_by!(title: "Risk")
      expect(risk.threat_ids_data.sole).to eq("system" => "https://attack.mitre.org", "id" => "https://attack.mitre.org/techniques/T1078")
      expect(risk.mitigating_factors_data.sole["description"]).to eq("MFA on every account")
      expect(risk.mitigating_factors_data.sole["uuid"]).to match(/\A[0-9a-f-]{36}\z/)
    end

    context "with an existing risk" do
      let!(:risk) do
        poam.poam_risks.create!(base_attrs.merge(
          uuid: SecureRandom.uuid,
          threat_ids_data: [ { "system" => "https://attack.mitre.org", "id" => "https://attack.mitre.org/techniques/T1078", "href" => "#t" } ],
          mitigating_factors_data: [ { "uuid" => "mf-1", "description" => "MFA", "props" => [ { "name" => "a", "value" => "b" } ] } ]
        ))
      end

      it "edits a factor in place, keeping its uuid, props and the threat's href" do
        patch poam_document_poam_risk_path(poam, risk), params: { poam_risk: {
          collections_present: "1",
          threat_ids_data: [ { system: "https://attack.mitre.org", id: "https://attack.mitre.org/techniques/T1078" } ],
          mitigating_factors_data: [ { uuid: "mf-1", description: "MFA, phishing-resistant" } ]
        } }

        risk.reload
        expect(risk.threat_ids_data.sole["href"]).to eq("#t")
        expect(risk.mitigating_factors_data.sole).to include("uuid" => "mf-1", "description" => "MFA, phishing-resistant")
        expect(risk.mitigating_factors_data.sole["props"]).to eq([ { "name" => "a", "value" => "b" } ])
      end

      it "refuses a threat ID that is not a URI, with a message, and saves nothing" do
        patch poam_document_poam_risk_path(poam, risk), params: { poam_risk: {
          remarks: "changed", collections_present: "1",
          threat_ids_data: [ { system: "https://attack.mitre.org", id: "T1190" } ]
        } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("A threat ID needs its system and its ID as full URIs")
        expect(risk.reload.remarks).to be_nil
        expect(risk.threat_ids_data.sole["id"]).to eq("https://attack.mitre.org/techniques/T1078")
      end

      it "clears both collections when every row is removed" do
        patch poam_document_poam_risk_path(poam, risk), params: { poam_risk: { collections_present: "1" } }

        expect(risk.reload.threat_ids_data).to eq([])
        expect(risk.mitigating_factors_data).to eq([])
      end

      it "leaves them alone when the form did not render them" do
        patch poam_document_poam_risk_path(poam, risk), params: { poam_risk: { remarks: "noted" } }

        expect(risk.reload.threat_ids_data.sole["id"]).to eq("https://attack.mitre.org/techniques/T1078")
        expect(risk.mitigating_factors_data.sole["uuid"]).to eq("mf-1")
      end
    end
  end
end
