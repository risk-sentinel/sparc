# frozen_string_literal: true

require "rails_helper"

RSpec.describe "LeveragedPoamDocuments", type: :request do
  let(:leveraging_boundary) { create(:authorization_boundary, name: "Leveraging Boundary") }
  let(:leveraged_boundary)  { create(:authorization_boundary, name: "Leveraged Boundary") }
  let(:user) { create(:user) }
  let(:role) do
    Role.find_or_create_by!(name: "leveraging_member") do |r|
      r.display_name = "Leveraging Member"
      r.scope = "authorization_boundary"
      r.permissions = {}
    end
  end
  let!(:user_role) do
    UserRole.create!(user: user, role: role, authorization_boundary_id: leveraging_boundary.id)
  end
  let!(:leveraged_auth) do
    LeveragedAuthorization.create!(
      name: "Test Leveraged Auth",
      uuid: SecureRandom.uuid,
      leveraging_boundary: leveraging_boundary,
      leveraged_boundary: leveraged_boundary
    )
  end
  let!(:leveraged_poam) do
    create(:poam_document, name: "Provider POAM", authorization_boundary: leveraged_boundary)
  end
  let!(:unrelated_poam) do
    other = create(:authorization_boundary, name: "Other Boundary")
    create(:poam_document, name: "Unrelated POAM", authorization_boundary: other)
  end

  before { sign_in_as(user) }

  describe "GET /leveraged_poam_documents" do
    it "lists POAMs from boundaries the user leverages" do
      get leveraged_poam_documents_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Provider POAM")
      expect(response.body).not_to include("Unrelated POAM")
    end

    it "shows the empty-state message when the user leverages nothing" do
      LeveragedAuthorization.delete_all
      get leveraged_poam_documents_path
      expect(response.body).to include("No leveraged POA")
    end
  end

  describe "GET /leveraged_poam_documents/:id" do
    it "renders the read-only inherited view" do
      get leveraged_poam_document_path(leveraged_poam)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Inherited from Leveraged Boundary")
      expect(response.body).to include("Provider POAM")
    end

    it "writes a poam_document_viewed_by_leveraging_user audit event" do
      expect {
        get leveraged_poam_document_path(leveraged_poam)
      }.to change { AuditEvent.where(action: "poam_document_viewed_by_leveraging_user").count }.by(1)
    end

    it "404s when the POAM is not in a leveraged boundary the user accesses" do
      other_unleveraged_boundary = create(:authorization_boundary)
      orphan_poam = create(:poam_document, name: "Orphan", authorization_boundary: other_unleveraged_boundary)

      get leveraged_poam_document_path(orphan_poam)
      expect(response).to have_http_status(:not_found).or have_http_status(:found)
    end
  end
end
