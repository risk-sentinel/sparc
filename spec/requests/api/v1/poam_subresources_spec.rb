# frozen_string_literal: true

require "rails_helper"

# #1010 — the six POA&M sub-objects that #832 left behind when it gave risks an
# API. They are the substance of a POA&M: what OSCAL exports.
#
# Written as one shared contract over five document-nested resources plus the
# two-deep milestones, because the six ARE one shape. Six near-identical spec
# files is how the six web controllers came to disagree in the first place.
RSpec.describe "Api::V1 POA&M sub-resources", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:document) { create(:poam_document, authorization_boundary: boundary) }

  let(:admin)  { create(:user, :admin) }
  let(:writer) { create(:user) }
  let(:reader) { create(:user) }

  let(:writer_role) { create(:role, :authorization_boundary_scoped, name: "poam_writer_#{SecureRandom.hex(4)}") }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    writer_role.assign_permissions("poam.write" => true, "poam.read" => true)
    writer_role.save!
    create(:user_role, user: writer, role: writer_role, authorization_boundary: boundary)
  end

  # Each resource: its path segment, its parameter key, and a minimal valid body.
  RESOURCES = {
    "items" => {
      key: :poam_item,
      attributes: { title: "Patch the thing", description: "Apply the vendor patch",
                    risk_status: "open" }
    },
    "observations" => {
      key: :poam_observation,
      attributes: { title: "Scanner reported drift", description: "Observed on the nightly run" }
    },
    # OSCAL requires a finding to name what it is a finding ABOUT, so
    # target_data is part of the minimal valid body rather than an extra.
    "findings" => {
      key: :poam_finding,
      attributes: { title: "AC-2 not satisfied", description: "Accounts are not reviewed",
                    target_data: { type: "statement-id", "target-id": "ac-2_smt",
                                   status: { state: "not-satisfied" } } }
    },
    "local_components" => {
      key: :poam_local_component,
      attributes: { title: "Edge proxy", description: "Terminates TLS",
                    component_type: "software" }
    }
  }.freeze

  RESOURCES.each do |segment, config|
    describe "/api/v1/poam_documents/:id/#{segment}" do
      let(:path) { "/api/v1/poam_documents/#{document.slug}/#{segment}" }
      let(:body) { { config[:key] => config[:attributes] } }

      it "creates the record, confirmed by an independent read" do
        post path, params: body, headers: headers_for(writer), as: :json

        expect(response).to have_http_status(:created), response.body
        id = response.parsed_body.dig("data", "id")

        get "#{path}/#{id}", headers: headers_for(writer)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("data", "title")).to eq(config[:attributes][:title])
        expect(response.parsed_body.dig("data", "description"))
          .to eq(config[:attributes][:description])
      end

      it "updates it, and the change is visible on a separate read" do
        post path, params: body, headers: headers_for(writer), as: :json
        id = response.parsed_body.dig("data", "id")

        patch "#{path}/#{id}", params: { config[:key] => { title: "Renamed by spec" } },
          headers: headers_for(writer), as: :json
        expect(response).to have_http_status(:ok), response.body

        get "#{path}/#{id}", headers: headers_for(writer)
        expect(response.parsed_body.dig("data", "title")).to eq("Renamed by spec")
      end

      it "deletes it, and it is gone from show AND from the index" do
        post path, params: body, headers: headers_for(writer), as: :json
        id = response.parsed_body.dig("data", "id")

        delete "#{path}/#{id}", headers: headers_for(writer)
        expect(response).to have_http_status(:ok)

        get "#{path}/#{id}", headers: headers_for(writer)
        expect(response).to have_http_status(:not_found)

        get path, headers: headers_for(writer)
        expect(response.parsed_body["data"].map { |r| r["id"] }).not_to include(id)
      end

      it "refuses a caller without poam.write, and creates nothing" do
        post path, params: body, headers: headers_for(reader), as: :json

        expect(response).to have_http_status(:forbidden)

        get path, headers: headers_for(admin)
        expect(response.parsed_body["data"]).to be_empty
      end

      it "refuses an unauthenticated caller" do
        post path, params: body, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it "refuses a field it does not accept rather than discarding it" do
        post path, params: { config[:key] => config[:attributes].merge(uuid: SecureRandom.uuid) },
          headers: headers_for(writer), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["details"].join(" ")).to include("uuid")
      end

      it "404s for a record belonging to another POA&M" do
        other = create(:poam_document, authorization_boundary: boundary)
        post "/api/v1/poam_documents/#{other.slug}/#{segment}", params: body,
          headers: headers_for(writer), as: :json
        foreign_id = response.parsed_body.dig("data", "id")

        get "#{path}/#{foreign_id}", headers: headers_for(writer)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "remediations and their milestones" do
    let(:risk) { create(:poam_risk, poam_document: document) }
    let(:remediations_path) { "/api/v1/poam_documents/#{document.slug}/remediations" }

    it "creates a remediation against a risk on this document" do
      post remediations_path,
        params: { poam_remediation: { title: "Rebuild the image", poam_risk_id: risk.id,
                                      lifecycle: "planned" } },
        headers: headers_for(writer), as: :json

      expect(response).to have_http_status(:created), response.body
      expect(response.parsed_body.dig("data", "poam_risk_id")).to eq(risk.id)
    end

    it "refuses a risk belonging to a different POA&M" do
      other_risk = create(:poam_risk, poam_document: create(:poam_document))

      post remediations_path,
        params: { poam_remediation: { title: "Should not attach",
                                      poam_risk_id: other_risk.id } },
        headers: headers_for(writer), as: :json

      expect(response).to have_http_status(:not_found)
      expect(other_risk.poam_remediations.count).to eq(0)
    end

    it "creates a milestone inside a remediation" do
      post remediations_path,
        params: { poam_remediation: { title: "Rebuild", poam_risk_id: risk.id } },
        headers: headers_for(writer), as: :json
      remediation_id = response.parsed_body.dig("data", "id")

      post "#{remediations_path}/#{remediation_id}/milestones",
        params: { poam_milestone: { title: "Image built", due_date: Date.current.iso8601 } },
        headers: headers_for(writer), as: :json

      expect(response).to have_http_status(:created), response.body
      expect(response.parsed_body.dig("data", "poam_remediation_id")).to eq(remediation_id)

      get "#{remediations_path}/#{remediation_id}", headers: headers_for(writer)
      expect(response.parsed_body.dig("data", "milestone_count")).to eq(1)
    end

    it "refuses a milestone on a remediation from another POA&M" do
      other_document = create(:poam_document)
      other_risk = create(:poam_risk, poam_document: other_document)
      foreign = create(:poam_remediation, poam_risk: other_risk)

      post "#{remediations_path}/#{foreign.id}/milestones",
        params: { poam_milestone: { title: "Should not attach" } },
        headers: headers_for(writer), as: :json

      expect(response).to have_http_status(:not_found)
      expect(foreign.poam_milestones.count).to eq(0)
    end

    it "refuses a caller without poam.write" do
      post remediations_path,
        params: { poam_remediation: { title: "Nope", poam_risk_id: risk.id } },
        headers: headers_for(reader), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
