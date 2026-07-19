# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::EvidenceControlLinks", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  let(:evidence) { create(:evidence) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_evidence_control_links_path(evidence_id: evidence.id)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/evidences/:evidence_id/control_links" do
    it "lists links for the evidence" do
      create_list(:evidence_control_link, 2, evidence: evidence)
      create(:evidence_control_link)  # belongs to other evidence

      get api_v1_evidence_control_links_path(evidence_id: evidence.id), headers: admin_headers

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(2)
      expect(parsed["meta"]).to include("page", "count")
    end

    it "accepts an evidence slug as the route key" do
      get api_v1_evidence_control_links_path(evidence_id: evidence.slug), headers: admin_headers
      expect(response).to have_http_status(:ok)
    end

    it "404s for unknown evidence" do
      get api_v1_evidence_control_links_path(evidence_id: 999_999), headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/evidences/:evidence_id/control_links" do
    it "links a bare control with no document scope" do
      expect {
        post api_v1_evidence_control_links_path(evidence_id: evidence.id),
             params: { control_link: { control_id: "AC-2" } }, headers: admin_headers
      }.to change(EvidenceControlLink, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["data"]["control_id"]).to eq("AC-2")
    end

    it "returns a JSON 400 (not an HTML page) when the root key is absent" do
      post api_v1_evidence_control_links_path(evidence_id: evidence.id),
           params: {}, headers: admin_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)["error"]).to match(/Missing required parameter/)
    end

    it "rejects a control_link with no control_id" do
      post api_v1_evidence_control_links_path(evidence_id: evidence.id),
           params: { control_link: { control_id: "" } }, headers: admin_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("Validation failed")
    end

    it "rejects an unknown document_type instead of constantizing it" do
      post api_v1_evidence_control_links_path(evidence_id: evidence.id),
           params: { control_link: { control_id: "AC-2", document_type: "Kernel", document_id: 1 } },
           headers: admin_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["details"].join(" ")).to match(/document_type must be one of/)
    end

    it "rejects a duplicate link for the same control + document scope" do
      create(:evidence_control_link, evidence: evidence, control_id: "AC-2")

      post api_v1_evidence_control_links_path(evidence_id: evidence.id),
           params: { control_link: { control_id: "AC-2" } }, headers: admin_headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # The #756 headline: a document-scoped link is what drives OSCAL output.
    context "when scoped to an SSP document" do
      let(:ssp) { create(:ssp_document) }

      it "creates a managed BackMatterResource carrying the durable resolver href" do
        expect {
          post api_v1_evidence_control_links_path(evidence_id: evidence.id),
               params: { control_link: { control_id: "AC-2", document_type: "SspDocument",
                                         document_id: ssp.id } },
               headers: admin_headers
        }.to change(BackMatterResource, :count).by(1)

        expect(response).to have_http_status(:created)

        resource = BackMatterResource.find_by(evidence: evidence, uuid: evidence.uuid)
        expect(resource.resourceable).to eq(ssp)
        expect(resource.source).to eq("managed")
        expect(resource.href).to eq(evidence.oscal_resolver_url)

        data = JSON.parse(response.body)["data"]
        expect(data["back_matter_resource_uuid"]).to eq(evidence.uuid)
        expect(data["oscal_href"]).to eq(evidence.oscal_resolver_url)
      end

      it "surfaces the evidence in the SSP's OSCAL back-matter" do
        post api_v1_evidence_control_links_path(evidence_id: evidence.id),
             params: { control_link: { control_id: "AC-2", document_type: "SspDocument",
                                       document_id: ssp.id } },
             headers: admin_headers
        expect(response).to have_http_status(:created)

        back_matter = ssp.reload.build_oscal_back_matter
        hrefs = back_matter["resources"].map { |r| r["rlinks"]&.first&.dig("href") || r["href"] }

        expect(hrefs.compact).to include(evidence.oscal_resolver_url)
      end
    end
  end

  describe "DELETE /api/v1/evidences/:evidence_id/control_links/:id" do
    it "unlinks the control" do
      link = create(:evidence_control_link, evidence: evidence)

      expect {
        delete api_v1_evidence_control_link_path(evidence_id: evidence.id, id: link.id),
               headers: admin_headers
      }.to change(EvidenceControlLink, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "tears down the back-matter resource when the last document-scoped link goes" do
      ssp  = create(:ssp_document)
      link = create(:evidence_control_link, evidence: evidence, control_id: "AC-2",
                    document_type: "SspDocument", document_id: ssp.id)
      expect(BackMatterResource.where(evidence: evidence).count).to eq(1)

      delete api_v1_evidence_control_link_path(evidence_id: evidence.id, id: link.id),
             headers: admin_headers

      expect(response).to have_http_status(:no_content)
      expect(BackMatterResource.where(evidence: evidence).count).to eq(0)
    end

    it "404s for a link belonging to different evidence" do
      other = create(:evidence_control_link)

      delete api_v1_evidence_control_link_path(evidence_id: evidence.id, id: other.id),
             headers: admin_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "authorization" do
    before { allow_any_instance_of(User).to receive(:has_permission?).and_return(false) }

    it "403s on read without evidence.read" do
      get api_v1_evidence_control_links_path(evidence_id: evidence.id), headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "403s on create without evidence.write" do
      post api_v1_evidence_control_links_path(evidence_id: evidence.id),
           params: { control_link: { control_id: "AC-2" } }, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
