# frozen_string_literal: true

require "rails_helper"

# SSP components had NO Api::V1 surface at all — they could be created, edited
# and deleted only through the enrichment screen, which makes the web UI the
# only way to perform those mutations. Found while adding validation modeling
# (#998): a validation component records a FIPS 140-2 certificate and the
# product it validates, and that is exactly the assertion an integrator needs to
# write from a pipeline.
#
# The posture is declared here rather than inherited from the environment —
# `has_permission?` short-circuits when no authentication is configured, and an
# authorization test that runs with the guard disabled asserts nothing while
# still reporting green.
RSpec.describe "Api::V1::SspComponents", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }

  let(:admin) { create(:user, :admin) }
  let(:auth_headers) { bearer_for(admin) }

  let(:reader) { create(:user).tap { |u| grant_permission(u, "ssp.read", authorization_boundary: boundary) } }
  let(:author) do
    create(:user).tap do |u|
      grant_permission(u, "ssp.read", authorization_boundary: boundary)
      grant_permission(u, "ssp.write", authorization_boundary: boundary)
    end
  end
  let(:outsider) { create(:user) }

  def bearer_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: "spec-#{user.id}").plaintext_token}" }
  end

  let!(:product) do
    ssp.ssp_components.create!(uuid: SecureRandom.uuid, component_type: "software",
                               title: "Acme Crypto Module", description: "The validated module.")
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_ssp_document_components_path(ssp)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "authorization, proven in both directions" do
    it "lets a boundary reader list components" do
      get api_v1_ssp_document_components_path(ssp), headers: bearer_for(reader)
      expect(response).to have_http_status(:ok)
    end

    it "refuses a caller holding nothing on the boundary" do
      get api_v1_ssp_document_components_path(ssp), headers: bearer_for(outsider)
      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a write from a reader" do
      post api_v1_ssp_document_components_path(ssp), headers: bearer_for(reader), as: :json,
           params: { ssp_component: { component_type: "software", title: "X", description: "Y" } }

      expect(response).to have_http_status(:forbidden)
      expect(ssp.ssp_components.count).to eq(1)
    end

    it "allows a write from a caller holding ssp.write on the boundary" do
      post api_v1_ssp_document_components_path(ssp), headers: bearer_for(author), as: :json,
           params: { ssp_component: { component_type: "software", title: "X", description: "Y" } }

      expect(response).to have_http_status(:created)
    end
  end

  describe "GET index" do
    it "lists this SSP's components and nobody else's" do
      other = create(:ssp_document, authorization_boundary: boundary)
      other.ssp_components.create!(uuid: SecureRandom.uuid, component_type: "software",
                                   title: "Elsewhere", description: "Another SSP.")

      get api_v1_ssp_document_components_path(ssp), headers: auth_headers

      titles = JSON.parse(response.body)["data"].map { |c| c["title"] }
      expect(titles).to eq([ "Acme Crypto Module" ])
    end

    it "filters by component_type" do
      ssp.ssp_components.create!(uuid: SecureRandom.uuid, component_type: "policy",
                                 title: "Acceptable Use", description: "A policy.")

      get api_v1_ssp_document_components_path(ssp), params: { component_type: "policy" },
          headers: auth_headers

      expect(JSON.parse(response.body)["data"].map { |c| c["component_type"] }).to eq([ "policy" ])
    end
  end

  describe "GET show" do
    it "resolves by uuid, which is what an OSCAL document carries" do
      get api_v1_ssp_document_component_path(ssp, product.uuid), headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "title")).to eq("Acme Crypto Module")
    end

    it "resolves by numeric id" do
      get api_v1_ssp_document_component_path(ssp, product.id), headers: auth_headers
      expect(response).to have_http_status(:ok)
    end

    it "404s for a component belonging to another SSP" do
      other = create(:ssp_document, authorization_boundary: boundary)
      stranger = other.ssp_components.create!(uuid: SecureRandom.uuid, component_type: "software",
                                              title: "Elsewhere", description: "Another SSP.")

      get api_v1_ssp_document_component_path(ssp, stranger.uuid), headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST create" do
    it "creates a component and mints a uuid when none is given" do
      expect {
        post api_v1_ssp_document_components_path(ssp), headers: auth_headers, as: :json,
             params: { ssp_component: { component_type: "policy", title: "Acceptable Use",
                                        description: "The AUP." } }
      }.to change { ssp.ssp_components.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body).dig("data", "uuid")).to be_present
    end

    it "records an audit event" do
      expect {
        post api_v1_ssp_document_components_path(ssp), headers: auth_headers, as: :json,
             params: { ssp_component: { component_type: "policy", title: "AUP", description: "x" } }
      }.to change { AuditEvent.where(action: "ssp_component_created").count }.by(1)
    end

    it "422s on a missing required field rather than creating half a component" do
      post api_v1_ssp_document_components_path(ssp), headers: auth_headers, as: :json,
           params: { ssp_component: { component_type: "policy" } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ── #998: the reason this endpoint exists ────────────────────────────────
  describe "recording a validation over the API" do
    let(:validation_payload) do
      {
        ssp_component: {
          component_type: "validation",
          title: "FIPS 140-2 certificate #4282",
          description: "NIST CMVP validation of the Acme Crypto Module.",
          validation_type: "fips-140-2",
          validation_reference: "4282",
          validation_details_href: "https://csrc.nist.gov/…/certificate/4282",
          validates_component_id: product.id
        }
      }
    end

    it "records the certificate and the product it is about" do
      post api_v1_ssp_document_components_path(ssp), headers: auth_headers, as: :json,
           params: validation_payload

      expect(response).to have_http_status(:created)
      validation = JSON.parse(response.body).dig("data", "validation")
      expect(validation["validation_type"]).to eq("fips-140-2")
      expect(validation["validation_reference"]).to eq("4282")
      expect(validation["validates_component_uuid"]).to eq(product.uuid)
    end

    it "reports the pairing from the product's side too" do
      post api_v1_ssp_document_components_path(ssp), headers: auth_headers, as: :json,
           params: validation_payload

      get api_v1_ssp_document_component_path(ssp, product.uuid), headers: auth_headers
      expect(JSON.parse(response.body).dig("data", "validated_by").first["title"])
        .to eq("FIPS 140-2 certificate #4282")
    end

    # An enum value with no supporting fields reads as support without being it,
    # and so does a field stored where nothing will ever read it.
    it "refuses a validation claim on a component that is not a validation" do
      post api_v1_ssp_document_components_path(ssp), headers: auth_headers, as: :json,
           params: { ssp_component: { component_type: "software", title: "Module",
                                      description: "x", validation_reference: "4282" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("validation")
    end

    it "refuses a pairing that points into another system security plan" do
      other = create(:ssp_document, authorization_boundary: boundary)
      stranger = other.ssp_components.create!(uuid: SecureRandom.uuid, component_type: "software",
                                              title: "Elsewhere", description: "Another SSP.")

      post api_v1_ssp_document_components_path(ssp), headers: auth_headers, as: :json,
           params: { ssp_component: { component_type: "validation", title: "Cert",
                                      description: "x", validates_component_id: stranger.id } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    # A validation component that asserts nothing yet must be distinguishable
    # from a component that is not a validation at all — an absent key does not
    # tell them apart.
    it "reports an empty validation block rather than omitting it" do
      post api_v1_ssp_document_components_path(ssp), headers: auth_headers, as: :json,
           params: { ssp_component: { component_type: "validation", title: "Cert pending",
                                      description: "Not yet issued." } }

      expect(JSON.parse(response.body).dig("data", "validation")).to include(
        "validation_type" => nil, "validation_reference" => nil
      )
    end
  end

  describe "PATCH update" do
    it "updates a component" do
      patch api_v1_ssp_document_component_path(ssp, product.uuid), headers: auth_headers, as: :json,
            params: { ssp_component: { title: "Acme Crypto Module v2" } }

      expect(response).to have_http_status(:ok)
      expect(product.reload.title).to eq("Acme Crypto Module v2")
    end

    it "records an audit event" do
      expect {
        patch api_v1_ssp_document_component_path(ssp, product.uuid), headers: auth_headers,
              as: :json, params: { ssp_component: { title: "Renamed" } }
      }.to change { AuditEvent.where(action: "ssp_component_updated").count }.by(1)
    end
  end

  describe "DELETE destroy" do
    it "deletes a component" do
      expect {
        delete api_v1_ssp_document_component_path(ssp, product.uuid), headers: auth_headers
      }.to change { ssp.ssp_components.count }.by(-1)

      expect(response).to have_http_status(:no_content)
    end

    # OSCAL requires the SSP to describe the system itself, and the enrichment
    # screen already protects this component from its own sync. An API that
    # could delete it would leave a document that cannot be exported.
    it "refuses to delete the this-system component" do
      this_system = ssp.ssp_components.create!(uuid: SecureRandom.uuid,
                                               component_type: "this-system",
                                               title: "This System", description: "The system.")

      delete api_v1_ssp_document_component_path(ssp, this_system.uuid), headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(this_system.reload).to be_persisted
    end

    it "records an audit event" do
      expect {
        delete api_v1_ssp_document_component_path(ssp, product.uuid), headers: auth_headers
      }.to change { AuditEvent.where(action: "ssp_component_deleted").count }.by(1)
    end
  end
end
