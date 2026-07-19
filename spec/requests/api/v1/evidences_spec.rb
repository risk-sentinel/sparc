# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Evidences", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def valid_attributes(overrides = {})
    {
      title: "API Evidence",
      description: "Created through the REST API",
      evidence_type: "artifact",
      status: "draft",
      source: "https://example.com/scanner"
    }.merge(overrides)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_evidences_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/evidences" do
    it "returns a paginated list for admin" do
      create_list(:evidence, 2)
      get api_v1_evidences_path, headers: admin_headers

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(2)
      expect(parsed["meta"]).to include("page", "count")
    end

    it "filters by type, status and free-text q" do
      create(:evidence, :scan_result, title: "Nessus sweep", status: "collected")
      create(:evidence, title: "Unrelated policy")

      get api_v1_evidences_path, params: { type: "scan_result" }, headers: admin_headers
      expect(JSON.parse(response.body)["data"].length).to eq(1)

      get api_v1_evidences_path, params: { status: "collected" }, headers: admin_headers
      expect(JSON.parse(response.body)["data"].length).to eq(1)

      get api_v1_evidences_path, params: { q: "Nessus" }, headers: admin_headers
      expect(JSON.parse(response.body)["data"].length).to eq(1)
    end

    it "filters by linked control_id" do
      linked = create(:evidence)
      create(:evidence_control_link, evidence: linked, control_id: "AC-2")
      create(:evidence)

      get api_v1_evidences_path, params: { control_id: "AC-2" }, headers: admin_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
      expect(parsed["data"].first["id"]).to eq(linked.id)
    end

    context "boundary scoping for non-admins" do
      let(:own_boundary)   { create(:authorization_boundary) }
      let(:other_boundary) { create(:authorization_boundary) }

      before do
        allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
        # Grant a real boundary-scoped role — stubbing `authorization_boundaries`
        # on `member` would not apply, since the controller loads its own User
        # instance from the bearer token.
        create(:user_role, user: member,
               role: create(:role, :authorization_boundary_scoped),
               authorization_boundary_id: own_boundary.id)
      end

      it "includes own-boundary and global evidence but excludes other boundaries" do
        mine   = create(:evidence, authorization_boundary: own_boundary)
        global = create(:evidence, authorization_boundary: nil)
        create(:evidence, authorization_boundary: other_boundary)

        get api_v1_evidences_path, headers: member_headers

        expect(response).to have_http_status(:ok)
        ids = JSON.parse(response.body)["data"].map { |e| e["id"] }
        expect(ids).to contain_exactly(mine.id, global.id)
      end
    end
  end

  describe "GET /api/v1/evidences/:id" do
    let(:evidence) { create(:evidence) }

    it "returns the detailed shape" do
      get api_v1_evidence_path(evidence.id), headers: admin_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data).to include("description", "oscal_resolver_url", "linked_control_ids", "file_hash")
      expect(data["uuid"]).to eq(evidence.uuid)
    end

    it "accepts a slug as the route key" do
      get api_v1_evidence_path(evidence.slug), headers: admin_headers
      expect(response).to have_http_status(:ok)
    end

    it "404s for unknown evidence" do
      get api_v1_evidence_path(999_999), headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/evidences" do
    it "creates metadata-only evidence" do
      expect {
        post api_v1_evidences_path, params: { evidence: valid_attributes }, headers: admin_headers
      }.to change(Evidence, :count).by(1)

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["title"]).to eq("API Evidence")
      expect(data["has_file"]).to be(false)
    end

    it "server-stamps collected_at / collected_by and ignores client-supplied values" do
      post api_v1_evidences_path,
           params: { evidence: valid_attributes(collected_by: "spoofed@example.com",
                                                collected_at: 10.years.ago.iso8601) },
           headers: admin_headers

      expect(response).to have_http_status(:created)
      evidence = Evidence.find(JSON.parse(response.body)["data"]["id"])
      expect(evidence.collected_by).to eq(admin.display_name.presence || admin.email)
      expect(evidence.collected_at).to be_within(1.minute).of(Time.current)
    end

    it "returns 422 with details when required fields are missing" do
      post api_v1_evidences_path, params: { evidence: { title: "No source or description" } },
           headers: admin_headers

      expect(response).to have_http_status(:unprocessable_entity)
      parsed = JSON.parse(response.body)
      expect(parsed["error"]).to eq("Validation failed")
      expect(parsed["details"].join(" ")).to match(/Description|Source/)
    end

    it "creates control links from an array of control_ids" do
      post api_v1_evidences_path,
           params: { evidence: valid_attributes(control_ids: [ "AC-2", "AU-12" ]) },
           headers: admin_headers

      expect(response).to have_http_status(:created)
      evidence = Evidence.find(JSON.parse(response.body)["data"]["id"])
      expect(evidence.linked_control_ids).to contain_exactly("AC-2", "AU-12")
    end

    it "creates control links from a comma-separated string (web-form shape)" do
      post api_v1_evidences_path,
           params: { evidence: valid_attributes(control_ids: "AC-2, AU-12") },
           headers: admin_headers

      evidence = Evidence.find(JSON.parse(response.body)["data"]["id"])
      expect(evidence.linked_control_ids).to contain_exactly("AC-2", "AU-12")
    end

    context "with a file upload" do
      let(:pdf) do
        Rack::Test::UploadedFile.new(
          StringIO.new("%PDF-1.4\nfake evidence artifact"), "application/pdf", true,
          original_filename: "evidence.pdf"
        )
      end

      it "attaches the file and computes provenance metadata" do
        post api_v1_evidences_path, params: { evidence: valid_attributes(file: pdf) },
             headers: admin_headers

        expect(response).to have_http_status(:created)
        data = JSON.parse(response.body)["data"]
        expect(data["has_file"]).to be(true)
        expect(data["original_filename"]).to eq("evidence.pdf")
        expect(data["file_hash"]).to be_present
        expect(data["file_size"]).to be_positive
      end

      it "rejects an executable upload with 422 (#509 deny-list)" do
        elf = Rack::Test::UploadedFile.new(
          StringIO.new("\x7fELF\x02\x01\x01#{'A' * 64}".b), "application/octet-stream", true,
          original_filename: "payload.bin"
        )

        expect {
          post api_v1_evidences_path, params: { evidence: valid_attributes(file: elf) },
               headers: admin_headers
        }.not_to change(Evidence, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to match(/Executable content is not permitted/)
      end
    end
  end

  describe "PATCH /api/v1/evidences/:id" do
    let(:evidence) { create(:evidence, status: "draft") }

    it "updates and returns the detailed shape" do
      patch api_v1_evidence_path(evidence.id),
            params: { evidence: { status: "collected", title: "Renamed" } },
            headers: admin_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["status"]).to eq("collected")
      expect(data["title"]).to eq("Renamed")
      expect(data).to include("description")
    end

    it "returns 422 when made invalid" do
      patch api_v1_evidence_path(evidence.id), params: { evidence: { title: "" } },
            headers: admin_headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/evidences/:id" do
    it "destroys the evidence" do
      evidence = create(:evidence)

      expect {
        delete api_v1_evidence_path(evidence.id), headers: admin_headers
      }.to change(Evidence, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["deleted"]).to be(true)
    end
  end

  describe "authorization" do
    let(:evidence) { create(:evidence) }

    before do
      allow_any_instance_of(User).to receive(:has_permission?).and_return(false)
    end

    it "403s on read without evidence.read" do
      get api_v1_evidences_path, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "403s on create without evidence.write" do
      post api_v1_evidences_path, params: { evidence: valid_attributes }, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "403s on destroy without evidence.write" do
      delete api_v1_evidence_path(evidence.id), headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
