# frozen_string_literal: true

require "rails_helper"

# #1092 — `threat_ids_data`, `mitigating_factors_data`, `origins_data` and
# `risk_log_data` are columns on both risk models, both exporters emit them, and
# the SAR parser populates them on import. Nothing could AUTHOR one: neither
# risk controller permitted them and no view mentioned them. Measured before
# this change: 0 of 17 SAR risks and 0 of 18 POA&M risks carried any.
#
# The collections are permitted as OSCAL SHAPES rather than opaque blobs, so
# both directions matter — the real keys have to survive, and a value that is not
# part of the shape must not be written into a jsonb column where it would
# resurface later as a schema-invalid export.
RSpec.describe "Risk OSCAL collections (#1092)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:admin)    { create(:user, :admin) }
  let(:token)    { ApiToken.generate!(user: admin, name: "Test") }
  let(:headers)  { { "Authorization" => "Bearer #{token.plaintext_token}" } }

  # OSCAL spells these hyphenated, and the parser stores them verbatim.
  let(:threat_ids) do
    [ { "system" => "http://fedramp.gov/ns/oscal", "id" => "TA-0001" } ]
  end
  let(:mitigating_factors) do
    [ { "uuid" => SecureRandom.uuid,
        "description" => "Egress is restricted to an allowlisted proxy.",
        "props" => [ { "name" => "control", "value" => "sc-7" } ] } ]
  end
  let(:origins) do
    [ { "actors" => [ { "type" => "party", "actor-uuid" => SecureRandom.uuid } ] } ]
  end
  let(:risk_log) do
    { "entries" => [ { "uuid" => SecureRandom.uuid,
                       "title" => "Triaged",
                       "start" => "2026-09-02T00:00:00Z" } ] }
  end

  shared_examples "authors the OSCAL collections" do
    it "accepts them, persists them, and reads them back" do
      patch update_path,
            params: { param_root => {
              threat_ids_data: threat_ids,
              mitigating_factors_data: mitigating_factors,
              origins_data: origins,
              risk_log_data: risk_log
            } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok), response.body
      risk.reload

      expect(risk.threat_ids_data.first["id"]).to eq("TA-0001")
      expect(risk.threat_ids_data.first["system"]).to eq("http://fedramp.gov/ns/oscal")
      expect(risk.mitigating_factors_data.first["description"])
        .to eq("Egress is restricted to an allowlisted proxy.")
      expect(risk.origins_data.first["actors"].first["type"]).to eq("party")
      expect(risk.risk_log_data["entries"].first["title"]).to eq("Triaged")

      data = JSON.parse(response.body)["data"]
      expect(data["threat_ids"].first["id"]).to eq("TA-0001")
      expect(data["mitigating_factors"].first["description"]).to be_present
      expect(data["origins"]).to be_present
      expect(data["risk_log"]["entries"]).to be_present
    end

    it "keeps the nested props on a mitigating factor" do
      patch update_path,
            params: { param_root => { mitigating_factors_data: mitigating_factors } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok), response.body
      expect(risk.reload.mitigating_factors_data.first["props"].first["value"]).to eq("sc-7")
    end

    # The other direction. A key outside the shape must not reach the column.
    it "does not write a key that is not part of the OSCAL shape" do
      patch update_path,
            params: { param_root => {
              threat_ids_data: [ { "system" => "http://x", "id" => "T-1",
                                   "not_an_oscal_key" => "dropped" } ]
            } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok), response.body
      stored = risk.reload.threat_ids_data.first
      expect(stored["id"]).to eq("T-1")
      expect(stored).not_to have_key("not_an_oscal_key")
    end

    it "leaves the collections alone when the request does not mention them" do
      risk.update!(threat_ids_data: threat_ids)

      patch update_path, params: { param_root => { title: "Renamed" } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok), response.body
      expect(risk.reload.threat_ids_data.first["id"]).to eq("TA-0001")
    end
  end

  describe "SAR risks" do
    let(:document) { create(:sar_document, authorization_boundary: boundary) }
    let!(:result)  { create(:sar_result, sar_document: document) }
    let(:risk) do
      result.sar_risks.create!(uuid: SecureRandom.uuid, title: "TLS downgrade",
                               description: "d", statement: "s", status: "open")
    end
    let(:update_path) { "/api/v1/sar_risks/#{risk.id}" }
    let(:param_root)  { :sar_risk }

    include_examples "authors the OSCAL collections"

    # SAR stores responses as jsonb; POA&M models them as real rows, so this is
    # deliberately asymmetric.
    it "also authors remediations, which are SAR-only" do
      patch update_path,
            params: { sar_risk: { remediations_data: [
              { "uuid" => SecureRandom.uuid, "lifecycle" => "planned",
                "title" => "Upgrade the TLS library",
                "description" => "Rebuild the image on the patched base." }
            ] } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok), response.body
      expect(risk.reload.remediations_data.first["lifecycle"]).to eq("planned")
    end
  end

  describe "POA&M risks" do
    let(:document) { create(:poam_document, authorization_boundary: boundary) }
    # `deadline` is REQUIRED on a POA&M risk and not on a SAR one — a POA&M item
    # with no time commitment is not a plan. Set here rather than worked around.
    let(:risk) do
      document.poam_risks.create!(uuid: SecureRandom.uuid, title: "TLS downgrade",
                                  description: "d", statement: "s", status: "open",
                                  deadline: 30.days.from_now)
    end
    let(:update_path) { "/api/v1/poam_risks/#{risk.id}" }
    let(:param_root)  { :poam_risk }

    include_examples "authors the OSCAL collections"
  end
end
