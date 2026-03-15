# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Control Catalogs Baseline Management", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:admin) { create(:user, :admin) }
  let(:catalog) { create(:control_catalog, lifecycle_status: "in_progress") }
  let(:family) { create(:control_family, control_catalog: catalog) }
  let!(:control1) { create(:catalog_control, control_family: family, control_id: "ac-1", baseline_impact: "LOW") }
  let!(:control2) { create(:catalog_control, control_family: family, control_id: "ac-2", baseline_impact: nil) }

  describe "PATCH /control_catalogs/:id/update_baseline" do
    it "updates baseline_impact on a single control" do
      sign_in(admin)
      patch update_baseline_control_catalog_path(catalog),
            params: { control_id: control1.id, baseline_impact: "LOW, MODERATE" },
            as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["baseline_impact"]).to eq("LOW, MODERATE")
      expect(control1.reload.baseline_impact).to eq("LOW, MODERATE")
    end

    it "clears baseline_impact when empty string sent" do
      sign_in(admin)
      patch update_baseline_control_catalog_path(catalog),
            params: { control_id: control1.id, baseline_impact: "" },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(control1.reload.baseline_impact).to be_nil
    end

    it "returns 404 for a control not in this catalog" do
      other_family = create(:control_family, control_catalog: create(:control_catalog))
      other_control = create(:catalog_control, control_family: other_family, control_id: "au-1")

      sign_in(admin)
      patch update_baseline_control_catalog_path(catalog),
            params: { control_id: other_control.id, baseline_impact: "HIGH" },
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "blocks updates on published catalogs" do
      catalog.update!(lifecycle_status: "published")
      sign_in(admin)
      patch update_baseline_control_catalog_path(catalog),
            params: { control_id: control1.id, baseline_impact: "HIGH" }

      expect(response).to redirect_to(control_catalog_path(catalog))
      expect(control1.reload.baseline_impact).to eq("LOW")
    end
  end

  describe "PATCH /control_catalogs/:id/bulk_update_baselines" do
    it "adds a level to multiple controls" do
      sign_in(admin)
      patch bulk_update_baselines_control_catalog_path(catalog),
            params: { control_ids: [ control1.id, control2.id ], baseline_level: "MODERATE", action_type: "add" },
            as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["updated_count"]).to eq(2)
      expect(control1.reload.baseline_impact).to eq("LOW, MODERATE")
      expect(control2.reload.baseline_impact).to eq("MODERATE")
    end

    it "removes a level from controls" do
      control2.update!(baseline_impact: "LOW, MODERATE")
      sign_in(admin)
      patch bulk_update_baselines_control_catalog_path(catalog),
            params: { control_ids: [ control1.id, control2.id ], baseline_level: "LOW", action_type: "remove" },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(control1.reload.baseline_impact).to be_nil
      expect(control2.reload.baseline_impact).to eq("MODERATE")
    end

    it "sets controls to only the specified level" do
      sign_in(admin)
      patch bulk_update_baselines_control_catalog_path(catalog),
            params: { control_ids: [ control1.id, control2.id ], baseline_level: "HIGH", action_type: "set" },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(control1.reload.baseline_impact).to eq("HIGH")
      expect(control2.reload.baseline_impact).to eq("HIGH")
    end

    it "clears baselines when set with empty level" do
      sign_in(admin)
      patch bulk_update_baselines_control_catalog_path(catalog),
            params: { control_ids: [ control1.id ], baseline_level: "", action_type: "set" },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(control1.reload.baseline_impact).to be_nil
    end

    it "returns error for empty control_ids" do
      sign_in(admin)
      patch bulk_update_baselines_control_catalog_path(catalog),
            params: { control_ids: [], baseline_level: "LOW", action_type: "add" },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "blocks updates on published catalogs" do
      catalog.update!(lifecycle_status: "published")
      sign_in(admin)
      patch bulk_update_baselines_control_catalog_path(catalog),
            params: { control_ids: [ control1.id ], baseline_level: "HIGH", action_type: "add" }

      expect(response).to redirect_to(control_catalog_path(catalog))
    end
  end
end
