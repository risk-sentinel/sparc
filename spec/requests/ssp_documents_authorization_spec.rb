# frozen_string_literal: true

require "rails_helper"

# #738 — confirms the BoundaryScopedDocument concern works for a *document* type
# (@ssp_document ivar convention + boundary/global scoping), complementing the
# Evidence reference spec.
RSpec.describe "SSP boundary-scoped access (#738)", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:boundary)       { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }

  let(:editor_role) do
    create(:role, :authorization_boundary_scoped, name: "ssp_editor",
           permissions: { "ssp.read" => true, "ssp.write" => true })
  end
  let(:viewer_role) do
    create(:role, :authorization_boundary_scoped, name: "ssp_viewer", permissions: { "ssp.read" => true })
  end

  def user_with(role, bound)
    u = create(:user)
    create(:user_role, user: u, role: role, authorization_boundary: bound)
    u
  end

  let(:editor)  { user_with(editor_role, boundary) }
  let(:viewer)  { user_with(viewer_role, boundary) }
  let(:outsider) { create(:user) }

  let!(:in_ssp)     { create(:ssp_document, name: "InBoundary SSP", authorization_boundary: boundary) }
  let!(:other_ssp)  { create(:ssp_document, name: "OtherBoundary SSP", authorization_boundary: other_boundary) }
  # #952 — a LEGACY boundary-less SSP. New ones cannot be created; rows written
  # before the rule exist on every upgraded instance, and until an admin
  # attaches them (#929) they must NOT be readable by everyone. This file used
  # to assert the opposite — "shows an outsider only globals" documented the
  # defect as intended behaviour.
  let!(:orphan_ssp) { create_legacy_orphan(:ssp_document, name: "Orphan SSP") }

  describe "GET /ssp_documents (index scoping)" do
    it "scopes a boundary member to their own boundary, and no further" do
      sign_in_as(editor)
      get ssp_documents_path
      expect(response.body).to include("InBoundary SSP")
      expect(response.body).not_to include("OtherBoundary SSP")
    end

    it "hides a boundary-less SSP from a boundary member (#952)" do
      sign_in_as(editor)
      get ssp_documents_path
      expect(response.body).not_to include("Orphan SSP")
    end

    it "shows an outsider nothing at all (#952)" do
      sign_in_as(outsider)
      get ssp_documents_path
      expect(response.body).not_to include("Orphan SSP")
      expect(response.body).not_to include("InBoundary SSP")
    end

    it "still shows an Instance-Admin the orphan, so it can be repaired" do
      sign_in_as(create(:user, :admin))
      get ssp_documents_path
      expect(response.body).to include("Orphan SSP")
    end
  end

  describe "read authorization" do
    it "allows in-boundary, blocks other-boundary" do
      sign_in_as(viewer)
      get ssp_document_path(in_ssp);     expect(response).to have_http_status(:ok)
      get ssp_document_path(other_ssp);  expect(response).to have_http_status(:redirect)
    end

    it "blocks a boundary member from reading a boundary-less SSP (#952)" do
      sign_in_as(viewer)
      get ssp_document_path(orphan_ssp)
      expect(response).to have_http_status(:redirect)
    end

    it "lets an Instance-Admin read it" do
      sign_in_as(create(:user, :admin))
      get ssp_document_path(orphan_ssp)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "write authorization" do
    it "blocks a read-only viewer from deleting" do
      sign_in_as(viewer)
      expect { delete ssp_document_path(in_ssp) }.not_to change(SspDocument, :count)
      expect(response).to have_http_status(:redirect)
    end

    it "lets an editor delete an in-boundary document" do
      sign_in_as(editor)
      expect { delete ssp_document_path(in_ssp) }.to change(SspDocument, :count).by(-1)
    end
  end
end
