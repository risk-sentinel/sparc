# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AuthorizationBoundaries", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:user) { create(:user) }
  let(:ab) { create(:authorization_boundary) }

  describe "GET /authorization_boundaries/:id/ato_wizard" do
    before { sign_in_as(user) }

    it "returns 200 for a signed-in user" do
      get ato_wizard_authorization_boundary_path(ab)
      expect(response).to have_http_status(:ok)
    end

    it "renders the ATO wizard page" do
      get ato_wizard_authorization_boundary_path(ab)
      expect(response.body).to include(ab.name)
    end
  end

  describe "POST /authorization_boundaries/:id/create_ato_package" do
    before { sign_in_as(user) }

    context "with skip-all params" do
      let(:params) do
        {
          profile_mode: "skip",
          cdef_mode: "skip",
          ssp_mode: "skip",
          sap_mode: "skip",
          sar_mode: "skip",
          poam_mode: "skip"
        }
      end

      it "redirects to the authorization boundary show page" do
        post create_ato_package_authorization_boundary_path(ab), params: params
        expect(response).to redirect_to(authorization_boundary_path(ab))
      end

      it "sets a success flash message" do
        post create_ato_package_authorization_boundary_path(ab), params: params
        follow_redirect!
        expect(response.body).to include("ATO package built")
      end
    end

    context "when an error occurs" do
      it "redirects to the wizard with an error message" do
        allow_any_instance_of(AtoPackageService)
          .to receive(:create)
          .and_raise(StandardError, "something went wrong")

        post create_ato_package_authorization_boundary_path(ab), params: {
          ssp_mode: "skip", sap_mode: "skip", sar_mode: "skip",
          poam_mode: "skip", cdef_mode: "skip", profile_mode: "skip"
        }
        expect(response).to redirect_to(ato_wizard_authorization_boundary_path(ab))
      end
    end
  end

  describe "GET /authorization_boundaries/:id/download_ato_package" do
    before { sign_in_as(user) }

    context "when documents are linked" do
      let(:ssp) { create(:ssp_document, :enriched, authorization_boundary: ab) }

      before do
        ssp # ensure created

        allow_any_instance_of(AtoPackageExportService)
          .to receive(:generate_zip)
          .and_return("PK\x03\x04fake-zip-data")
      end

      it "returns a ZIP file" do
        get download_ato_package_authorization_boundary_path(ab)

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/zip")
        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.headers["Content-Disposition"]).to include("ato_package")
      end
    end

    context "when no documents are linked" do
      it "returns a ZIP file (with only manifest)" do
        allow_any_instance_of(AtoPackageExportService)
          .to receive(:generate_zip)
          .and_return("PK\x03\x04fake-zip-data")

        get download_ato_package_authorization_boundary_path(ab)

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/zip")
      end
    end
  end
end
