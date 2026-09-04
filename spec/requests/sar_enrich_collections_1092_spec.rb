# frozen_string_literal: true

require "rails_helper"

# #1092 (UI half) — the enrich form can now author a risk's `threat-ids` and
# `mitigating-factors`, in the risk card the operator is already editing.
#
# The form submits risks with EMPTY-BRACKET notation
# (`sar_document[risks][][title]`), grouped positionally by Rack. Nested
# repeatables inside that do work — verified directly, including the case most
# likely to break it, a risk with no rows between two that have them — which is
# why this lives in the existing card rather than on a screen of its own.
RSpec.describe "SAR enrich risk collections (#1092)", type: :request do
  let(:user)     { create(:user, :admin) }
  let(:document) { create(:sar_document, name: "Collections SAR") }
  let!(:result)  { create(:sar_result, sar_document: document) }
  let!(:risk) do
    result.sar_risks.create!(uuid: SecureRandom.uuid, title: "TLS downgrade",
                             description: "d", statement: "s", status: "open")
  end

  before { sign_in_as(user) }

  def submit(risk_attrs)
    patch update_enrich_sar_document_path(document),
          params: { sar_document: { risks: [ risk_attrs ] } }
  end

  def base_attrs(extra = {})
    { id: risk.id, sar_result_id: risk.sar_result_id, title: risk.title,
      description: risk.description, statement: risk.statement,
      status: risk.status, collections_present: "1" }.merge(extra)
  end

  it "renders the collection editors inside the risk card" do
    get enrich_sar_document_path(document)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("sar_document[risks][][threat_ids_data][][id]")
    expect(response.body).to include("sar_document[risks][][mitigating_factors_data][][description]")
    expect(response.body).to include("collections_present")
  end

  it "saves threat IDs and mitigating factors typed into the card" do
    submit(base_attrs(
      threat_ids_data: [ { system: "http://fedramp.gov/ns/oscal", id: "TA-0001" } ],
      mitigating_factors_data: [ { description: "Egress restricted to a proxy." } ]
    ))

    risk.reload
    expect(risk.threat_ids_data.first["id"]).to eq("TA-0001")
    expect(risk.threat_ids_data.first["system"]).to eq("http://fedramp.gov/ns/oscal")
    expect(risk.mitigating_factors_data.first["description"]).to eq("Egress restricted to a proxy.")
  end

  # OSCAL requires a uuid on a mitigating-factor, and a row cloned from the
  # <template> carries none — a template cannot mint a distinct id per clone.
  it "assigns a uuid to a factor that arrived without one" do
    submit(base_attrs(mitigating_factors_data: [ { description: "Compensating control." } ]))

    factor = risk.reload.mitigating_factors_data.first
    expect(factor["uuid"]).to be_present
    expect(factor["uuid"]).to match(/\A[0-9a-f-]{36}\z/)
  end

  it "keeps the uuid a factor already had rather than minting a new one" do
    existing = SecureRandom.uuid
    risk.update!(mitigating_factors_data: [ { "uuid" => existing, "description" => "First" } ])

    submit(base_attrs(mitigating_factors_data: [ { uuid: existing, description: "Edited" } ]))

    factor = risk.reload.mitigating_factors_data.first
    expect(factor["uuid"]).to eq(existing)
    expect(factor["description"]).to eq("Edited")
  end

  # The deletion case, which is the one an absent key would silently break.
  it "clears a collection when every row is removed" do
    risk.update!(threat_ids_data: [ { "system" => "http://x", "id" => "T-1" } ])

    submit(base_attrs) # no threat_ids_data key at all, but collections_present

    expect(risk.reload.threat_ids_data).to eq([])
  end

  # ...and the other direction: a form that never rendered them must not wipe
  # them, which is what protects the API-authored values.
  it "leaves a collection untouched when the form did not render it" do
    risk.update!(threat_ids_data: [ { "system" => "http://x", "id" => "T-1" } ])

    submit(base_attrs.except(:collections_present))

    expect(risk.reload.threat_ids_data.first["id"]).to eq("T-1")
  end

  it "drops a blank row rather than storing an empty object" do
    submit(base_attrs(
      threat_ids_data: [ { system: "", id: "" }, { system: "http://x", id: "T-2" } ],
      mitigating_factors_data: [ { description: "" } ]
    ))

    risk.reload
    expect(risk.threat_ids_data.length).to eq(1)
    expect(risk.threat_ids_data.first["id"]).to eq("T-2")
    expect(risk.mitigating_factors_data).to eq([])
  end

  # The grouping case that made this look impossible at first.
  it "keeps each risk's rows with the right risk when one has none" do
    second = result.sar_risks.create!(uuid: SecureRandom.uuid, title: "Second",
                                      description: "d", statement: "s", status: "open")
    third = result.sar_risks.create!(uuid: SecureRandom.uuid, title: "Third",
                                     description: "d", statement: "s", status: "open")

    patch update_enrich_sar_document_path(document), params: { sar_document: { risks: [
      base_attrs(threat_ids_data: [ { system: "http://x", id: "T-1" } ]),
      { id: second.id, sar_result_id: second.sar_result_id, title: second.title,
        description: "d", statement: "s", status: "open", collections_present: "1" },
      { id: third.id, sar_result_id: third.sar_result_id, title: third.title,
        description: "d", statement: "s", status: "open", collections_present: "1",
        threat_ids_data: [ { system: "http://x", id: "T-3" } ] }
    ] } }

    expect(risk.reload.threat_ids_data.first["id"]).to eq("T-1")
    expect(second.reload.threat_ids_data).to eq([])
    expect(third.reload.threat_ids_data.first["id"]).to eq("T-3")
  end
end
