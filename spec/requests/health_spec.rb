# frozen_string_literal: true

require "rails_helper"

# #1151 — liveness and readiness. Both directions for every condition: a probe
# that could only ever answer 200 is the `/nginx-health` problem again.
RSpec.describe "Health endpoints" do
  def connection = ActiveRecord::Base.connection

  before { HealthController.reset_cache! }

  after do
    HealthController.reset_cache!
    AuthorizationBoundary.reset_column_information
  end

  describe "GET /up (liveness)" do
    it "answers 200 with no session and no credentials" do
      get "/up"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("status" => "ok")
    end

    it "does not touch the database — liveness must survive the database being down" do
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get "/up" }

      expect(queries).to be_empty
    end
  end

  describe "GET /up/ready (readiness)" do
    it "answers 200 when the database answers, nothing is pending and the schema matches" do
      get "/up/ready"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "status" => "ok",
        "checks" => { "database" => "ok", "pending_migrations" => 0, "schema_drift" => 0 }
      )
    end

    it "answers 503 on schema drift — the v1.16.2 case" do
      connection.remove_column(:authorization_boundaries, :security_objective_integrity)

      get "/up/ready"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["status"]).to eq("unavailable")
      expect(response.parsed_body.dig("checks", "schema_drift")).to eq(1)
    end

    it "never names what drifted in an unauthenticated response" do
      connection.remove_column(:authorization_boundaries, :security_objective_integrity)

      get "/up/ready"

      expect(response.body).not_to include("authorization_boundaries")
      expect(response.body).not_to include("security_objective_integrity")
    end

    it "answers 503 when a migration is pending" do
      context = ActiveRecord::Base.connection_pool.migration_context
      allow(ActiveRecord::Base.connection_pool).to receive(:migration_context).and_return(context)
      allow(context).to receive(:open).and_return(instance_double(ActiveRecord::Migrator, pending_migrations: [ :one ]))

      get "/up/ready"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("checks", "pending_migrations")).to eq(1)
    end

    it "answers 503 when the database does not answer, without trying the schema" do
      allow(ActiveRecord::Base.connection).to receive(:select_value).and_call_original
      allow(ActiveRecord::Base.connection).to receive(:select_value).with("SELECT 1")
                                                                     .and_raise(ActiveRecord::ConnectionNotEstablished)
      expect(SchemaDriftService).not_to receive(:new)

      get "/up/ready"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["checks"]).to eq("database" => "unavailable")
    end

    it "measures the schema at most once per cache window — a probe must not become a query storm" do
      expect(SchemaDriftService).to receive(:new).once.and_call_original

      3.times { get "/up/ready" }

      expect(response).to have_http_status(:ok)
    end

    it "measures again once the window has passed" do
      allow(HealthController).to receive(:clock).and_return(1_000.0, 1_000.0 + HealthController::CACHE_TTL + 1)
      expect(SchemaDriftService).to receive(:new).twice.and_call_original

      2.times { get "/up/ready" }
    end
  end
end
