# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Catalog Revalidate (#237)", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:admin) { create(:user, :admin) }
  let(:catalog) { create(:control_catalog, status: "completed") }

  let(:viewer_role) do
    create(:role, name: "global_viewer", scope: "instance",
           permissions: { "catalogs.read" => true })
  end

  let(:viewer_user) do
    user = create(:user)
    create(:user_role, user: user, role: viewer_role)
    user
  end

  describe "PATCH /control_catalogs/:id/revalidate" do
    it "requires authentication" do
      patch revalidate_control_catalog_path(catalog)
      expect(response).to redirect_to(login_path)
    end

    it "requires catalog write permission" do
      sign_in_as(viewer_user)
      patch revalidate_control_catalog_path(catalog)
      expect(response).to redirect_to(root_path)
    end

    context "as admin" do
      before { sign_in_as(admin) }

      it "re-runs validation and updates metadata_extra" do
        patch revalidate_control_catalog_path(catalog)

        expect(response).to redirect_to(control_catalog_path(catalog))
        follow_redirect!

        catalog.reload
        expect(catalog.metadata_extra["import_warnings"]).to be_an(Array)
        expect(catalog.metadata_extra["import_warnings_summary"]).to be_a(Hash)
        expect(catalog.metadata_extra["last_validated_at"]).to be_present
      end

      it "sets a success flash message" do
        patch revalidate_control_catalog_path(catalog)
        expect(flash[:success]).to match(/Quality validation refreshed/)
      end

      it "stores the validation timestamp" do
        patch revalidate_control_catalog_path(catalog)
        catalog.reload
        expect(catalog.metadata_extra["last_validated_at"]).to be_present
      end
    end
  end
end
