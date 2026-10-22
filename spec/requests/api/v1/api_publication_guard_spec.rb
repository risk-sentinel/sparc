# frozen_string_literal: true

require "rails_helper"

# Owner, 2026-10-21: publishing through the API (`lifecycle_status:
# "published"` on create or update) is restricted to a document that went
# through the publication process, or a caller with the credentials to approve
# it. Before, any caller with write access could publish by PATCH, skipping
# review and approval even with SPARC_REQUIRE_DOCUMENT_APPROVAL on.
RSpec.describe "Publishing through the API", type: :request do
  let(:writer) { create(:user) }
  let(:approver) { create(:user) }

  def bearer(user) = { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'caller').plaintext_token}" }

  # Writers hold every write key and no approve key; approvers hold the approve keys too.
  def grant(user, approve:)
    allow(user).to receive(:instance_administrator?).and_return(false)
    allow_any_instance_of(User).to receive(:has_permission?) do |u, key, **|
      key = key.to_s
      key.end_with?(".read", ".write") || (approve && u.id == approver.id && key.end_with?(".approve"))
    end
    allow_any_instance_of(User).to receive(:has_role?).and_return(false)
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:api_auth_mode).and_return("local")
    grant(writer, approve: false)
    grant(approver, approve: true)
  end

  describe "a catalog (approval workflow)" do
    let(:catalog) { create(:control_catalog, lifecycle_status: "in_progress") }

    def publish(user)
      patch "/api/v1/control_catalogs/#{catalog.slug}",
            params: { control_catalog: { lifecycle_status: "published" } }, headers: bearer(user), as: :json
    end

    it "is refused to a writer while the catalog is not approved, and audited" do
      expect { publish(writer) }.to change { AuditEvent.where(action: "api_publication_refused").count }.by(1)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["details"].join).to match(/submit it for review/)
      expect(catalog.reload.lifecycle_status).to eq("in_progress")
    end

    it "is allowed to a writer once the catalog is approved" do
      catalog.update!(approval_status: "approved")

      publish(writer)

      expect(response).to have_http_status(:ok)
      expect(catalog.reload.lifecycle_status).to eq("published")
    end

    it "is allowed to a caller who may approve it" do
      publish(approver)

      expect(response).to have_http_status(:ok)
      expect(catalog.reload.lifecycle_status).to eq("published")
    end

    it "is allowed to a policy_manager" do
      allow_any_instance_of(User).to receive(:has_role?) { |u, role| u.id == writer.id && role == "policy_manager" }

      publish(writer)

      expect(catalog.reload.lifecycle_status).to eq("published")
    end

    it "leaves every other change alone" do
      patch "/api/v1/control_catalogs/#{catalog.slug}",
            params: { control_catalog: { description: "edited" } }, headers: bearer(writer), as: :json

      expect(response).to have_http_status(:ok)
      expect(catalog.reload.description).to eq("edited")
    end

    it "refuses creating a catalog already published, unless the caller may approve" do
      post "/api/v1/control_catalogs", params: { control_catalog: { name: "Direct", lifecycle_status: "published" } },
                                       headers: bearer(writer), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(ControlCatalog.find_by(name: "Direct")).to be_nil
    end
  end

  describe "a profile and a CDEF (approval workflow)" do
    it "refuses an unapproved profile to a writer" do
      profile = create(:profile_document, lifecycle_status: "in_progress")

      patch "/api/v1/profile_documents/#{profile.slug}",
            params: { profile_document: { lifecycle_status: "published" } }, headers: bearer(writer), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(profile.reload.lifecycle_status).to eq("in_progress")
    end

    it "refuses an unapproved CDEF to a writer" do
      cdef = create(:cdef_document, lifecycle_status: "in_progress")

      patch "/api/v1/cdef_documents/#{cdef.slug}",
            params: { cdef_document: { lifecycle_status: "published" } }, headers: bearer(writer), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(cdef.reload.lifecycle_status).to eq("in_progress")
    end
  end

  # No approval workflow: the checks the web Publish button makes.
  describe "an SSP" do
    let(:boundary) { create(:authorization_boundary) }

    def publish(ssp)
      patch "/api/v1/ssp_documents/#{ssp.slug}",
            params: { ssp_document: { lifecycle_status: "published" } }, headers: bearer(writer), as: :json
    end

    it "is refused while its metadata fails the publication checks" do
      ssp = create(:ssp_document, authorization_boundary: boundary, lifecycle_status: "in_progress", metadata_extra: {})
      allow_any_instance_of(SspDocument).to receive(:content_complete?).and_return(true)

      publish(ssp)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["details"].join).to match(/Not ready to publish: .*role is required/)
      expect(ssp.reload.lifecycle_status).to eq("in_progress")
    end

    it "is refused while its content is incomplete" do
      ssp = create(:ssp_document, authorization_boundary: boundary, lifecycle_status: "in_progress")
      allow_any_instance_of(PublicationValidationService).to receive(:validate)
        .and_return(PublicationValidationService::Result.new(valid?: true, errors: [], missing_fields: []))
      allow_any_instance_of(SspDocument).to receive(:content_complete?).and_return(false)

      publish(ssp)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["details"].join).to match(/Not ready to publish: missing/)
    end

    it "is allowed once it passes them" do
      ssp = create(:ssp_document, authorization_boundary: boundary, lifecycle_status: "in_progress")
      allow_any_instance_of(PublicationValidationService).to receive(:validate)
        .and_return(PublicationValidationService::Result.new(valid?: true, errors: [], missing_fields: []))
      allow_any_instance_of(SspDocument).to receive(:content_complete?).and_return(true)

      publish(ssp)

      expect(ssp.reload.lifecycle_status).to eq("published")
    end
  end
end
