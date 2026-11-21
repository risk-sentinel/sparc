# frozen_string_literal: true

require "rails_helper"

# #1354 — push keys and Class A on Settings → Connections, the Class A
# materials form, and how an unconfirmed push and a material read on the
# boundary's Received documents.
#
# NIST SP 800-53: AC-3, AC-5, CA-3, CA-6, AU-12.
RSpec.describe "Settings → Connections: push and Class A (web)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:admin) { create(:user, :admin) }
  let(:manager) { create(:user).tap { |u| grant(u, "connections.manage") } }
  let(:key) { OpenSSL::PKey.generate_key("ED25519") }
  let!(:connection) do
    ExchangeConnection.create!(name: "Acme trust center", authorization_boundary: boundary, certification_class: "A",
                               root_url: "https://trust.acme.example/", auth_scheme: "none")
  end

  def grant(user, *keys, boundary: nil)
    role = create(:role, scope: boundary ? "authorization_boundary" : "instance", permissions: keys.index_with { true })
    create(:user_role, user: user, role: role, authorization_boundary_id: boundary&.id)
  end

  def pdf(text = "%PDF-1.7 report") = Rack::Test::UploadedFile.new(StringIO.new(text), "application/pdf", original_filename: "soc2.pdf")

  it "saves a pasted PEM key and the Class A framework and date from the form, and audits them" do
    sign_in_as(manager)

    patch admin_exchange_connection_path(connection), params: { exchange_connection: {
      push_public_keys: key.public_to_pem, class_a_framework: "fedramp_ready", class_a_certified_on: "2026-01-10"
    } }

    expect(response).to redirect_to(admin_exchange_connection_path(connection))
    connection.reload
    expect(connection.push_public_keys).to eq([ Base64.strict_encode64(key.raw_public_key) ])
    expect(connection.class_a_expires_on).to eq(Date.new(2027, 1, 10))
    event = AuditEvent.where(action: "exchange_connection_updated").last
    expect(event.metadata).to include("push_keys" => [ ExchangeConnection.key_fingerprint(connection.push_public_keys.first) ],
                                      "class_a_framework" => "fedramp_ready")
  end

  it "shows the form's push and Class A fields" do
    sign_in_as(admin)
    get edit_admin_exchange_connection_path(connection)

    expect(response.body).to include("Ed25519 public keys", "Class A certification", "SOC 2 Type II", "GovRAMP")
  end

  it "shows the push card with key fingerprints and receipts, and the Class A card with its expiry" do
    connection.update!(push_public_keys: [ Base64.strict_encode64(key.raw_public_key) ], class_a_framework: "soc2_type2",
                       class_a_certified_on: Date.current - 13.months, last_push_status: "unconfirmed")
    ExchangePushReceipt.create!(exchange_connection: connection, sha256: "c" * 64, signature_sha256: "3" * 64,
                                key_fingerprint: "f" * 16, signed_at: Time.current, status: "unconfirmed",
                                reason: "The registered address could not be pulled")
    sign_in_as(admin)

    get admin_exchange_connection_path(connection)

    expect(response.body).to include("Accepting pushes", "SHA-256 #{ExchangeConnection.key_fingerprint(connection.push_public_keys.first)}")
    expect(response.body).to include("/api/v1/exchange_connections/#{connection.id}/document_sources/")
    expect(response.body).to include("The registered address could not be pulled")
    expect(response.body).to include("data-testid=\"class-a-expired\"", "Expired: FedRAMP asks for a certification")

    get admin_exchange_connections_path
    expect(response.body).to include("connection-unconfirmed-push", "class-a-expired")
  end

  it "says a connection that is not Class A records no Class A materials" do
    connection.update!(certification_class: "B")
    sign_in_as(admin)
    get admin_exchange_connection_path(connection)

    expect(response.body).to include("Recorded only for a Class A connection")
    expect(response.body).not_to include("class-a-material-form")
  end

  describe "adding a material" do
    it "stores it for review on the boundary, and says unchanged for the same file again" do
      sign_in_as(manager)

      post admin_exchange_connection_certification_materials_path(connection), params: { kind: "soc2_report", file: pdf }
      expect(response).to redirect_to(admin_exchange_connection_path(connection, anchor: "class-a"))
      expect(flash[:success]).to include("waits for a reviewer of #{boundary.name}")
      doc = ReceivedDocument.certification_materials.sole
      expect(doc).to have_attributes(received_by: manager, document_type: "soc2_report", state: "pending_review")

      post admin_exchange_connection_certification_materials_path(connection), params: { kind: "soc2_report", file: pdf }
      expect(flash[:warning]).to include("already on record")

      get admin_exchange_connection_path(connection)
      expect(response.body).to include("SOC 2 Type II complete report", "soc2.pdf")
    end

    it "explains a refusal, and asks for a file" do
      sign_in_as(manager)

      post admin_exchange_connection_certification_materials_path(connection), params: { kind: "nope", file: pdf }
      expect(flash[:error]).to include("Not added")
      post admin_exchange_connection_certification_materials_path(connection), params: { kind: "soc2_report" }
      expect(flash[:error]).to include("Choose a file")
    end

    it "refuses a user without connections.manage" do
      sign_in_as(create(:user))
      post admin_exchange_connection_certification_materials_path(connection), params: { kind: "soc2_report", file: pdf }

      expect(response).not_to have_http_status(:success)
      expect(ReceivedDocument.count).to eq(0)
    end
  end

  describe "on the boundary's Received documents" do
    let(:reviewer) { create(:user).tap { |u| grant(u, "evidence.read", "exchange.review", boundary: boundary) } }

    it "shows a material as unchecked and downloadable as its file, decided by someone other than its uploader" do
      doc = CertificationMaterialService.call(connection: connection, kind: "bridge_letter", bytes: "%PDF letter",
                                              filename: "letter.pdf", content_type: "application/pdf",
                                              received_by: manager).document
      sign_in_as(reviewer)

      get authorization_boundary_received_document_path(boundary, doc)
      expect(response.body).to include("Bridge or gap letter", "material-not-checked", "Not compared: a Class A material")
      expect(response.body).to include("data-testid=\"review-accept\"")

      # Its uploader is offered no decision (AC-5).
      grant(manager, "evidence.read", "exchange.review", boundary: boundary)
      sign_in_as(manager)
      get authorization_boundary_received_document_path(boundary, doc)
      expect(response.body).to include("data-testid=\"review-sod\"")
      expect(response.body).not_to include("data-testid=\"review-accept\"")
      sign_in_as(reviewer)

      get file_authorization_boundary_received_document_path(boundary, doc)
      expect(response.media_type).to eq("application/pdf")

      post accept_authorization_boundary_received_document_path(boundary, doc)
      expect(doc.reload.state).to eq("accepted")

      get authorization_boundary_received_documents_path(boundary)
      expect(response.body).to include("Class A material")
    end

    it "flags an unconfirmed push on the version and in the list" do
      doc = create(:received_document, authorization_boundary: boundary, exchange_connection: connection, source: "push",
                                       push_confirmed: false)
      sign_in_as(reviewer)

      get authorization_boundary_received_document_path(boundary, doc)
      expect(response.body).to include("Unconfirmed push", "Check with the provider before accepting")

      get authorization_boundary_received_documents_path(boundary)
      expect(response.body).to include("data-testid=\"unconfirmed-push\"")
    end

    it "says a confirmed push was confirmed" do
      doc = create(:received_document, authorization_boundary: boundary, source: "pull", push_confirmed: true)
      sign_in_as(reviewer)

      get authorization_boundary_received_document_path(boundary, doc)
      expect(response.body).to include("Confirmed: the registered address returned these exact bytes")
    end
  end
end
