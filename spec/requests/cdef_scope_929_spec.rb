# frozen_string_literal: true

require "rails_helper"

# #929 — a CDEF's scope could be set at upload and changed by no route.
# The web action and its Api::V1 twin, so the UI stays a thin client.
RSpec.describe "CDEF scope re-assignment (#929)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:cdef)   { create(:cdef_document) }
  let(:target) { create(:authorization_boundary, name: "Target ATO") }
  let!(:target_env) { create(:boundary, authorization_boundary: target) }

  let(:writer) do
    user = create(:user)
    grant_permission(user, "cdef.write")
    user
  end

  describe "PATCH /cdef_documents/:id/update_scope" do
    it "scopes a CDEF to a boundary from the show screen's picker" do
      sign_in_as(writer)

      patch "/cdef_documents/#{cdef.slug}/update_scope",
            params: { cdef_document: { scope: "boundary", authorization_boundary_id: target.id } }

      expect(BoundaryCdefDocument.where(cdef_document_id: cdef.id).pluck(:boundary_id))
        .to contain_exactly(target_env.id)
      expect(CdefScopeService.current_boundary_id(cdef.reload)).to eq(target.id)
    end

    it "makes a CDEF globally available" do
      sign_in_as(writer)
      CdefScopeService.apply(cdef, scope: "boundary", authorization_boundary_id: target.id)

      patch "/cdef_documents/#{cdef.slug}/update_scope",
            params: { cdef_document: { scope: "global" } }

      expect(cdef.reload.globally_available).to be(true)
      expect(BoundaryCdefDocument.where(cdef_document_id: cdef.id)).to be_empty
    end

    it "works on a PUBLISHED CDEF — scope is an assignment, not content" do
      sign_in_as(writer)
      published = create(:cdef_document, lifecycle_status: "published")

      patch "/cdef_documents/#{published.slug}/update_scope",
            params: { cdef_document: { scope: "boundary", authorization_boundary_id: target.id } }

      expect(CdefScopeService.current_boundary_id(published.reload)).to eq(target.id)
    end

    it "refuses a caller without cdef.write" do
      sign_in_as(create(:user))

      patch "/cdef_documents/#{cdef.slug}/update_scope",
            params: { cdef_document: { scope: "boundary", authorization_boundary_id: target.id } }

      expect(BoundaryCdefDocument.where(cdef_document_id: cdef.id)).to be_empty
      expect(response).to redirect_to(root_path)
    end

    it "reports the AWS Labs read-only rule instead of half-applying it" do
      sign_in_as(writer)
      upstream = create(:cdef_document, import_metadata: { "source_type" => "aws_labs" })

      patch "/cdef_documents/#{upstream.slug}/update_scope",
            params: { cdef_document: { scope: "boundary", authorization_boundary_id: target.id } }

      expect(flash[:error]).to match(/AWS Labs/i)
      expect(BoundaryCdefDocument.where(cdef_document_id: upstream.id)).to be_empty
    end
  end

  describe "PATCH /api/v1/cdef_documents/:id/scope" do
    def token_headers(user)
      { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'Test').plaintext_token}" }
    end

    it "scopes a CDEF to a boundary and returns the detailed shape" do
      patch "/api/v1/cdef_documents/#{cdef.slug}/scope",
            params: { scope: "boundary", authorization_boundary_id: target.id },
            headers: token_headers(writer)

      expect(response).to have_http_status(:ok)
      expect(CdefScopeService.current_boundary_id(cdef.reload)).to eq(target.id)
    end

    it "refuses a caller without cdef.write" do
      patch "/api/v1/cdef_documents/#{cdef.slug}/scope",
            params: { scope: "boundary", authorization_boundary_id: target.id },
            headers: token_headers(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(BoundaryCdefDocument.where(cdef_document_id: cdef.id)).to be_empty
    end

    it "422s an unusable scope rather than 500ing" do
      patch "/api/v1/cdef_documents/#{cdef.slug}/scope",
            params: { scope: "boundary" },
            headers: token_headers(writer)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires a token" do
      patch "/api/v1/cdef_documents/#{cdef.slug}/scope",
            params: { scope: "global" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
