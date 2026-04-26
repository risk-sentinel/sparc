# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::BackMatterResources", type: :request do
  let(:admin)        { create(:user, :admin) }
  let(:admin_token)  { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }
  let(:boundary)     { create(:authorization_boundary) }
  let(:ssp)          { create(:ssp_document, authorization_boundary: boundary) }
  let(:resource) do
    BackMatterResource.create!(resourceable: ssp, title: "Policy",
                               uuid: SecureRandom.uuid, source: "managed")
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def role_for(name, scope:)
    Role.find_or_create_by!(name: name) do |r|
      r.display_name = name.titleize
      r.scope = scope
      r.permissions = {}
    end
  end

  def user_with_role(name, boundary_id: nil, perms: {})
    user = create(:user)
    role = role_for(name, scope: boundary_id ? "authorization_boundary" : "instance")
    role.update!(permissions: role.permissions.merge(perms)) if perms.any?
    UserRole.create!(user: user, role: role, authorization_boundary_id: boundary_id)
    user
  end

  def headers_for(user)
    token = ApiToken.generate!(user: user, name: "Test #{user.id}")
    { "Authorization" => "Bearer #{token.plaintext_token}" }
  end

  # ── Authentication backfill (closes #375 spec gap) ─────────────────────

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_back_matter_resources_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ── Existing #375 endpoints — minimal happy-path backfill ──────────────

  describe "GET /api/v1/back_matter_resources (#375 backfill)" do
    it "returns paginated list for admin" do
      resource
      get api_v1_back_matter_resources_path, headers: admin_headers
      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]).to be_an(Array)
      expect(parsed["data"].length).to eq(1)
      expect(parsed["meta"]).to include("page", "count")
    end

    it "filters by source" do
      resource
      BackMatterResource.create!(resourceable: ssp, title: "Imp",
                                 uuid: SecureRandom.uuid, source: "imported")
      get api_v1_back_matter_resources_path, params: { source: "imported" }, headers: admin_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].map { |d| d["source"] }).to eq([ "imported" ])
    end
  end

  describe "POST /api/v1/back_matter_resources (#375 backfill)" do
    it "creates a managed resource for admin" do
      post api_v1_back_matter_resources_path, headers: admin_headers,
           params: { back_matter_resource: { title: "New", resourceable_type: "SspDocument",
                                             resourceable_id: ssp.id } }
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body).dig("data", "source")).to eq("managed")
    end

    it "denies non-admin creation of authoritative resources" do
      writer = user_with_role("writer_role", perms: { "back_matter.write" => true })
      post api_v1_back_matter_resources_path, headers: headers_for(writer),
           params: { back_matter_resource: { title: "Auth", source: "authoritative",
                                             resourceable_type: "SspDocument",
                                             resourceable_id: ssp.id } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ── #372 bulk endpoint ─────────────────────────────────────────────────

  describe "POST /api/v1/back_matter_resources/bulk" do
    it "creates multiple resources and returns per-row results" do
      post bulk_api_v1_back_matter_resources_path, headers: admin_headers, as: :json,
           params: { entries: [
             { title: "B1", href: "https://x.gov/b1.pdf" },
             { title: "B2", href: "https://x.gov/b2.pdf" },
             { title: "" } # error row
           ] }

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["imported"].size).to eq(2)
      expect(data["errors"].size).to eq(1)
      expect(data["batch_uuid"]).to be_present
    end

    it "denies callers without bulk_import or write" do
      bystander = create(:user)
      post bulk_api_v1_back_matter_resources_path,
           headers: headers_for(bystander), as: :json,
           params: { entries: [ { title: "x" } ] }
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ── #372 promotion endpoints ───────────────────────────────────────────

  describe "POST /api/v1/back_matter_resources/:id/promote" do
    it "transitions to pending_review for admin" do
      post promote_api_v1_back_matter_resource_path(resource), headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(resource.reload.promotion_status).to eq("pending_review")
    end

    it "rejects users without back_matter.promote permission" do
      bystander = create(:user)
      post promote_api_v1_back_matter_resource_path(resource), headers: headers_for(bystander)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 409 when promotion already pending" do
      resource.update!(promotion_status: "pending_review")
      post promote_api_v1_back_matter_resource_path(resource), headers: admin_headers
      expect(response).to have_http_status(:conflict)
    end
  end

  describe "POST /api/v1/back_matter_resources/:id/approve_promotion" do
    before { resource.update!(promotion_status: "pending_review") }

    it "approves with admin actor — flips to authoritative + globally_available" do
      post approve_promotion_api_v1_back_matter_resource_path(resource), headers: admin_headers
      expect(response).to have_http_status(:ok)
      resource.reload
      expect(resource.source).to eq("authoritative")
      expect(resource.globally_available).to eq(true)
      expect(resource.approved_by_user_id).to eq(admin.id)
    end

    it "approves when actor is AO of the resource boundary" do
      ao_user = user_with_role("ao", boundary_id: boundary.id)
      post approve_promotion_api_v1_back_matter_resource_path(resource), headers: headers_for(ao_user)
      expect(response).to have_http_status(:ok)
    end

    it "rejects unauthorized actors with 403" do
      bystander = create(:user)
      post approve_promotion_api_v1_back_matter_resource_path(resource), headers: headers_for(bystander)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 409 when not pending_review" do
      resource.update!(promotion_status: "none")
      post approve_promotion_api_v1_back_matter_resource_path(resource), headers: admin_headers
      expect(response).to have_http_status(:conflict)
    end
  end

  describe "POST /api/v1/back_matter_resources/:id/reject_promotion" do
    before { resource.update!(promotion_status: "pending_review") }

    it "rejects with reason from admin" do
      post reject_promotion_api_v1_back_matter_resource_path(resource), headers: admin_headers,
           params: { reason: "needs more detail" }
      expect(response).to have_http_status(:ok)
      expect(resource.reload.promotion_status).to eq("rejected")
      expect(resource.rejection_reason).to eq("needs more detail")
    end

    it "returns 422 with no reason" do
      post reject_promotion_api_v1_back_matter_resource_path(resource), headers: admin_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/back_matter_resources/promotion_queue" do
    let!(:pending_a) do
      r = BackMatterResource.create!(resourceable: ssp, title: "A",
                                     uuid: SecureRandom.uuid, source: "managed")
      r.update!(promotion_status: "pending_review")
      r
    end
    let!(:pending_other_boundary) do
      other_boundary = create(:authorization_boundary)
      other_ssp = create(:ssp_document, authorization_boundary: other_boundary)
      r = BackMatterResource.create!(resourceable: other_ssp, title: "Other",
                                     uuid: SecureRandom.uuid, source: "managed")
      r.update!(promotion_status: "pending_review")
      r
    end
    let!(:not_pending) do
      BackMatterResource.create!(resourceable: ssp, title: "Done",
                                 uuid: SecureRandom.uuid, source: "managed",
                                 promotion_status: "approved")
    end

    it "shows all pending resources to admin" do
      get promotion_queue_api_v1_back_matter_resources_path, headers: admin_headers
      expect(response).to have_http_status(:ok)
      titles = JSON.parse(response.body)["data"].map { |r| r["title"] }
      expect(titles).to match_array([ "A", "Other" ])
    end

    it "scopes to AO's boundary only" do
      ao_user = user_with_role("ao", boundary_id: boundary.id)
      get promotion_queue_api_v1_back_matter_resources_path, headers: headers_for(ao_user)
      titles = JSON.parse(response.body)["data"].map { |r| r["title"] }
      expect(titles).to eq([ "A" ])
    end
  end
end
