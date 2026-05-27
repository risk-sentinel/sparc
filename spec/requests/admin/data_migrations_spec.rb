# frozen_string_literal: true

require "rails_helper"

# v1.8.3 — admin status page for deferred data migrations.
RSpec.describe "Admin::DataMigrations", type: :request do
  let(:admin)   { create(:user, :admin) }
  let(:regular) { create(:user) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "GET /admin/data_migrations" do
    it "renders with status summary + table for admin" do
      DataMigrationRun.create!(name: "PromoteFoo", status: "pending")
      DataMigrationRun.create!(name: "PromoteBar", status: "completed",
                                started_at: 2.minutes.ago, completed_at: 30.seconds.ago,
                                records_processed: 42)
      DataMigrationRun.create!(name: "PromoteBaz", status: "failed",
                                error_message: "PG::Foo: explosion")

      sign_in_as(admin)
      get admin_data_migrations_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("PromoteFoo")
      expect(response.body).to include("PromoteBar")
      expect(response.body).to include("PromoteBaz")
      expect(response.body).to include("pending")
      expect(response.body).to include("completed")
      expect(response.body).to include("failed")
      # Status counters
      expect(response.body).to include("1</strong> pending")
      expect(response.body).to include("1</strong> completed")
      expect(response.body).to include("1</strong> failed")
    end

    it "shows the empty-state copy when no rows exist" do
      sign_in_as(admin)
      get admin_data_migrations_path
      expect(response.body).to include("No deferred data migrations")
    end

    it "is forbidden for non-admin users" do
      sign_in_as(regular)
      get admin_data_migrations_path
      expect(response).to have_http_status(:found).or have_http_status(:forbidden)
    end
  end
end
