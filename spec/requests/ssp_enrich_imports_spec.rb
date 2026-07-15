# frozen_string_literal: true

require "rails_helper"

# #737 — SSP enrichment imports from canonical SPARC sources.
RSpec.describe "SSP enrich imports (#737)", type: :request do
  let(:user) { create(:user, :admin) }

  before { sign_in_as(user) }

  describe "POST /ssp_documents/:id/import_boundary_users" do
    let(:boundary) { create(:authorization_boundary) }
    let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }

    before do
      AuthorizationBoundaryMembership.create!(authorization_boundary: boundary, user_name: "Jane AO", role: "authorizing_official")
      AuthorizationBoundaryMembership.create!(authorization_boundary: boundary, user_name: "John SO", role: "system_owner")
    end

    it "imports boundary members as system users" do
      expect { post import_boundary_users_ssp_document_path(ssp) }.to change { ssp.ssp_users.count }.by(2)
      expect(response).to redirect_to(enrich_ssp_document_path(ssp))
      expect(ssp.ssp_users.pluck(:title)).to include("Jane AO", "John SO")
    end

    it "is idempotent — does not duplicate members already present" do
      ssp.ssp_users.create!(uuid: SecureRandom.uuid, title: "Jane AO")
      expect { post import_boundary_users_ssp_document_path(ssp) }.to change { ssp.ssp_users.count }.by(1)
      expect(ssp.ssp_users.where(title: "Jane AO").count).to eq(1)
    end
  end
end
