# frozen_string_literal: true

require "rails_helper"

# #1354 — Settings → Connections (Admin::ExchangeConnectionsController and
# Admin::ExchangeDocumentSourcesController). Both directions of the guard
# (an administrator and a connections.manage holder in; anyone else out), the
# write-only credential, the audit trail, and Pull now / Discover / Test
# connection wired to the services the API uses.
#
# NIST SP 800-53: AC-3, CA-3, IA-5, AU-12.
RSpec.describe "Settings → Connections (web)", type: :request do
  # The guards no-op unless sign-in is on; declare the posture (issue rules).
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:admin) { create(:user, :admin) }
  let(:manager) { create(:user).tap { |u| grant(u, "connections.manage") } }
  let(:outsider) { create(:user) }
  let(:secret) { "tok-#{SecureRandom.hex(12)}" }
  let!(:connection) do
    ExchangeConnection.create!(name: "Acme trust center", authorization_boundary: boundary,
                               root_url: "https://trust.acme.example/", auth_scheme: "bearer", credential: secret)
  end

  def grant(user, *keys, boundary: nil)
    role = create(:role, scope: boundary ? "authorization_boundary" : "instance",
                         permissions: keys.index_with { true })
    create(:user_role, user: user, role: role, authorization_boundary_id: boundary&.id)
  end

  def connection_params(overrides = {})
    { exchange_connection: { name: "New provider", authorization_boundary_id: boundary.id,
                             root_url: "https://trust.provider.example/", auth_scheme: "none",
                             fedramp_id: "FR2401234567", certification_class: "B", certification_type: "20x",
                             spki_sha256: "", allowed_cidrs: "", enabled: "1" }.merge(overrides) }
  end

  describe "who is let in" do
    it "admits an instance administrator and a connections.manage holder" do
      [ admin, manager ].each do |user|
        sign_in_as(user)
        get admin_exchange_connections_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme trust center")
      end
    end

    it "refuses a signed-in user without connections.manage, on every screen and action" do
      sign_in_as(outsider)
      source = connection.document_sources.create!(url: "https://trust.acme.example/vdr.json", format: "fedramp")

      get admin_exchange_connections_path
      expect(response).to redirect_to(root_path)
      get admin_exchange_connection_path(connection)
      expect(response).to redirect_to(root_path)
      get new_admin_exchange_connection_path
      expect(response).to redirect_to(root_path)

      expect { post admin_exchange_connections_path, params: connection_params }.not_to change(ExchangeConnection, :count)
      expect { delete admin_exchange_connection_path(connection) }.not_to change(ExchangeConnection, :count)
      patch admin_exchange_connection_path(connection), params: { exchange_connection: { name: "Hijacked" } }
      expect(connection.reload.name).to eq("Acme trust center")

      expect(ExchangePullService).not_to receive(:call)
      post pull_admin_exchange_connection_path(connection)
      expect(response).to redirect_to(root_path)

      expect {
        post admin_exchange_connection_document_sources_path(connection),
             params: { exchange_document_source: { url: "https://trust.acme.example/x.json", format: "fedramp" } }
      }.not_to change(ExchangeDocumentSource, :count)
      expect { delete admin_exchange_connection_document_source_path(connection, source) }.not_to change(ExchangeDocumentSource, :count)
    end

    it "does not offer the Connections links to someone the screen refuses, and offers them to a manager" do
      sign_in_as(outsider)
      get root_path
      expect(response.body).not_to include(admin_exchange_connections_path)

      sign_in_as(manager)
      get root_path
      expect(response.body).to include(admin_exchange_connections_path)
    end
  end

  describe "the credential" do
    before { sign_in_as(admin) }

    it "is never rendered: only whether one is set" do
      [ admin_exchange_connections_path, admin_exchange_connection_path(connection),
        edit_admin_exchange_connection_path(connection) ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(secret)
      end
      get admin_exchange_connection_path(connection)
      expect(response.body).to match(/Credential<\/th><td[^>]*>Set</)
    end

    it "is kept when the form leaves it blank, replaced when typed, cleared when asked" do
      patch admin_exchange_connection_path(connection), params: { exchange_connection: { name: "Renamed", credential: "" } }
      expect(connection.reload.credential).to eq(secret)

      patch admin_exchange_connection_path(connection), params: { exchange_connection: { credential: "replacement" } }
      expect(connection.reload.credential).to eq("replacement")

      patch admin_exchange_connection_path(connection), params: { exchange_connection: { clear_credential: "1" } }
      expect(connection.reload.credential?).to be(false)
    end
  end

  describe "create, update, delete" do
    before { sign_in_as(manager) }

    it "creates a connection with its pins and audits it" do
      pin = "a" * 64
      expect {
        post admin_exchange_connections_path,
             params: connection_params(spki_sha256: "#{pin}\n", allowed_cidrs: "203.0.113.0/24, 198.51.100.0/24")
      }.to change(ExchangeConnection, :count).by(1)

      created = ExchangeConnection.find_by!(name: "New provider")
      expect(response).to redirect_to(admin_exchange_connection_path(created))
      expect(created).to have_attributes(spki_sha256: [ pin ], allowed_cidrs: %w[203.0.113.0/24 198.51.100.0/24],
                                         created_by: manager, fedramp_id: "FR2401234567")
      event = AuditEvent.where(action: "exchange_connection_created").last
      expect(event.metadata).to include("connection_id" => created.id, "name" => "New provider")
    end

    it "re-renders the form with the reason when the connection is invalid" do
      expect {
        post admin_exchange_connections_path, params: connection_params(root_url: "http://plain.example/")
      }.not_to change(ExchangeConnection, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must be an https:// address")
    end

    it "updates and deletes, auditing each" do
      patch admin_exchange_connection_path(connection), params: { exchange_connection: { name: "Acme (renamed)" } }
      expect(connection.reload.name).to eq("Acme (renamed)")
      expect(AuditEvent.where(action: "exchange_connection_updated").last.metadata["changed"]).to include("name")

      expect { delete admin_exchange_connection_path(connection) }.to change(ExchangeConnection, :count).by(-1)
      expect(response).to redirect_to(admin_exchange_connections_path)
      expect(AuditEvent.where(action: "exchange_connection_deleted").last.metadata["connection_id"]).to eq(connection.id)
    end

    it "adds, edits and removes a document to pull" do
      expect {
        post admin_exchange_connection_document_sources_path(connection),
             params: { exchange_document_source: { url: "https://trust.acme.example/package/vdr.json", format: "fedramp",
                                                   pull_interval_hours: "12" } }
      }.to change(connection.document_sources, :count).by(1)
      source = connection.document_sources.last
      expect(source.pull_interval_hours).to eq(12)

      get edit_admin_exchange_connection_document_source_path(connection, source)
      expect(response).to have_http_status(:ok)
      patch admin_exchange_connection_document_source_path(connection, source),
            params: { exchange_document_source: { pull_interval_hours: "48" } }
      expect(source.reload.pull_interval_hours).to eq(48)

      expect { delete admin_exchange_connection_document_source_path(connection, source) }
        .to change(ExchangeDocumentSource, :count).by(-1)
      expect(AuditEvent.where(action: "exchange_connection_updated", subject_id: connection.id).count).to eq(3)
    end

    it "shows the document sources with their last status and error" do
      connection.document_sources.create!(url: "https://trust.acme.example/vdr.json", format: "fedramp",
                                          last_status: "failed", last_error: "TLS key does not match the pin",
                                          last_pulled_at: Time.current)
      get admin_exchange_connection_path(connection)
      expect(response.body).to include("https://trust.acme.example/vdr.json", "TLS key does not match the pin")
    end
  end

  describe "Pull now, Discover, Test connection" do
    before { sign_in_as(manager) }

    it "pulls each enabled document through ExchangePullService and reports the results" do
      enabled = connection.document_sources.create!(url: "https://trust.acme.example/vdr.json", format: "fedramp")
      connection.document_sources.create!(url: "https://trust.acme.example/old.json", format: "fedramp", enabled: false)
      expect(ExchangePullService).to receive(:call).once.with(enabled, user: manager)
        .and_return(ExchangePullService::Result.new(status: :failed, error: "connection refused"))

      post pull_admin_exchange_connection_path(connection)
      expect(response).to redirect_to(admin_exchange_connection_path(connection))
      expect(flash[:error]).to include("vdr.json: failed — connection refused")
    end

    it "says there is nothing to pull when no document is enabled" do
      expect(ExchangePullService).not_to receive(:call)
      post pull_admin_exchange_connection_path(connection)
      expect(flash[:warning]).to include("no enabled documents")
    end

    it "lists discovered documents with an Add form, and pulls nothing" do
      allow(ExchangeConnectionProbe).to receive(:discover).with(connection).and_return(
        root_url: connection.root_url,
        candidates: [ { url: "https://trust.acme.example/package/sdr.json", hint_format: "json", registered: false } ]
      )
      expect(ExchangePullService).not_to receive(:call)

      expect { post discover_admin_exchange_connection_path(connection) }.not_to change(ExchangeDocumentSource, :count)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("https://trust.acme.example/package/sdr.json", "data-testid=\"add-discovered\"")
    end

    it "shows a discovery failure" do
      allow(ExchangeConnectionProbe).to receive(:discover)
        .and_raise(ExchangeConnectionProbe::Error.new(:dns, "could not resolve trust.acme.example"))
      post discover_admin_exchange_connection_path(connection)
      expect(response.body).to include("could not resolve trust.acme.example")
    end

    it "shows each document's test result and stores nothing" do
      source = connection.document_sources.create!(url: "https://trust.acme.example/vdr.json", format: "fedramp")
      allow(ExchangeConnectionProbe).to receive(:test).with(connection).and_return(
        root: { url: connection.root_url, reachable: false, reason: "dns", error: "could not resolve" },
        sources: [ { url: source.url, document_source_id: source.id, reachable: true, status: 200, bytes: 120,
                     validation: { valid: false, format: "fedramp", error_count: 1,
                                   errors: [ { check: "completeness", pointer: "/reportPeriod/to", message: "required field is blank" } ] } } ]
      )

      expect { post test_connection_admin_exchange_connection_path(connection) }.not_to change(ReceivedDocument, :count)
      expect(response.body).to include("could not resolve", "/reportPeriod/to", "required field is blank")
      expect(source.reload.last_pulled_at).to be_nil
    end
  end
end
