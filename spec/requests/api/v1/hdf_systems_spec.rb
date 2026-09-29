# frozen_string_literal: true

require "rails_helper"

# #1179 — GET /api/v1/authorization_boundaries/:id/hdf_system
RSpec.describe "Api::V1::HdfSystems", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  let(:boundary) { create(:authorization_boundary, name: "Portal Production") }
  let(:environment) { create(:boundary, authorization_boundary: boundary) }

  before do
    # Declared, never inherited from .env: the permission guards short-circuit
    # when no auth is configured, and a spec that inherits that posture asserts
    # nothing (#947).
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    # The CLI leg is covered in the service spec (and skipped where there is no
    # binary). Here only the in-process schema gate runs, on every host.
    allow(HdfSystemExportService).to receive(:cli_available?).and_return(false)

    cdef = create(:cdef_document, name: "Web tier", component_type: "software")
    create(:boundary_cdef_document, boundary: environment, cdef_document: cdef)
  end

  def path(key = boundary)
    api_v1_authorization_boundary_hdf_system_path(key)
  end

  def grant(user, *permissions, on: boundary)
    role = create(:role, :authorization_boundary_scoped,
                  permissions: permissions.index_with { true })
    create(:user_role, user: user, role: role, authorization_boundary: on)
  end

  it "returns 401 without a token" do
    get path
    expect(response).to have_http_status(:unauthorized)
  end

  describe "the document" do
    it "is the raw hdf-system artefact, schema-valid" do
      get path, headers: admin_headers

      expect(response).to have_http_status(:ok)
      doc = JSON.parse(response.body)
      expect(doc["systemId"]).to eq(boundary.uuid)
      expect(doc["name"]).to eq("Portal Production")
      expect(doc["components"].size).to eq(1)
      expect(Hdf::SystemSchema.errors(doc)).to eq([])
    end

    it "resolves the boundary by uuid, id or slug — the uuid form is the systemRef" do
      [ boundary.uuid, boundary.id.to_s, boundary.slug ].each do |key|
        get path(key), headers: admin_headers
        expect(response).to have_http_status(:ok), "lookup by #{key.inspect} returned #{response.status}"
        expect(JSON.parse(response.body)["systemId"]).to eq(boundary.uuid)
      end
    end

    it "returns 404 for an unknown boundary" do
      get path(SecureRandom.uuid), headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "authorization — both permissions, on THIS boundary" do
    it "allows a member holding authorization_boundaries.read and ssp.read on the boundary" do
      grant(member, "authorization_boundaries.read", "ssp.read")

      get path, headers: member_headers
      expect(response).to have_http_status(:ok)
    end

    it "forbids a member with no grant" do
      get path, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    # The document carries SSP implementation narrative, so boundary read
    # alone must not reach it.
    it "forbids a member with authorization_boundaries.read but not ssp.read" do
      grant(member, "authorization_boundaries.read")

      get path, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a member with ssp.read but not authorization_boundaries.read" do
      grant(member, "ssp.read")

      get path, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a member whose grants are on a DIFFERENT boundary" do
      grant(member, "authorization_boundaries.read", "ssp.read", on: create(:authorization_boundary))

      get path, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "ETag" do
    it "is strong, and is the SHA-256 of the exact response bytes" do
      get path, headers: admin_headers

      etag = response.headers["ETag"]
      expect(etag).not_to start_with("W/")
      expect(etag).to eq(%("#{Digest::SHA256.hexdigest(response.body)}"))
    end

    it "answers 304 with no body when If-None-Match matches" do
      get path, headers: admin_headers
      etag = response.headers["ETag"]

      get path, headers: admin_headers.merge("If-None-Match" => etag)
      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
    end

    it "answers 200 with a new tag after the boundary changes" do
      get path, headers: admin_headers
      etag = response.headers["ETag"]

      boundary.update!(description: "Now described")
      get path, headers: admin_headers.merge("If-None-Match" => etag)

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    # The reason the tag is over the bytes and not over updated_at: adding a
    # system owner changes the document without touching the boundary row.
    it "changes when the system owner changes, though the boundary row does not" do
      get path, headers: admin_headers
      etag = response.headers["ETag"]
      stamp = boundary.reload.updated_at

      create(:authorization_boundary_membership, authorization_boundary: boundary,
             role: "system_owner", user_email: "so@example.gov")
      expect(boundary.reload.updated_at).to eq(stamp)

      get path, headers: admin_headers.merge("If-None-Match" => etag)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["owner"]).to eq("identifier" => "so@example.gov", "type" => "email")
    end
  end

  describe "audit" do
    it "records hdf_system_exported on a 200" do
      expect { get path, headers: admin_headers }
        .to change { AuditEvent.where(action: "hdf_system_exported").count }.by(1)

      event = AuditEvent.where(action: "hdf_system_exported").last
      expect(event.metadata).to include("components" => 1, "excluded_components" => 0)
    end

    it "records nothing on a 304 — nothing was exported" do
      get path, headers: admin_headers
      etag = response.headers["ETag"]

      expect { get path, headers: admin_headers.merge("If-None-Match" => etag) }
        .not_to change { AuditEvent.where(action: "hdf_system_exported").count }
    end

    it "records nothing when the request is forbidden" do
      expect { get path, headers: member_headers }
        .not_to change { AuditEvent.where(action: "hdf_system_exported").count }
    end
  end

  describe "422" do
    it "names the gap when the boundary has no components" do
      empty = create(:authorization_boundary)

      get path(empty), headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/cannot be exported as an hdf-system document/)
      expect(body["details"]).to match(/has no components/)
    end

    it "does not return a document the CLI refuses" do
      allow(HdfSystemExportService).to receive(:cli_available?).and_return(true)
      allow_any_instance_of(HdfRunner).to receive(:validate).and_raise(
        HdfRunner::Error.new("invalid", command: "hdf validate", exit_code: 1, stderr: "bad")
      )

      get path, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to match(/validation failed/)
    end

    it "does not return a document the schema refuses" do
      allow_any_instance_of(HdfSystemExportService).to receive(:build).and_return(
        "name" => "x", "components" => []
      )

      get path, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["details"]).to include(a_string_starting_with("/components:"))
    end
  end
end
