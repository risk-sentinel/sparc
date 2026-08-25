# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SapDocuments", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }
  let(:boundary) { create(:authorization_boundary) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_sap_documents_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # #844 — the generator has existed since #28 and the UI has driven it since,
  # but the API exposed only CRUD, so an integrator could create an EMPTY SAP
  # shell and nothing else. This is the endpoint that closes that gap.
  describe "POST /api/v1/sap_documents/generate" do
    let!(:ssp) { create(:ssp_document, authorization_boundary: boundary) }

    before do
      create(:ssp_control, ssp_document: ssp, control_id: "AC-2", title: "Account Management")
      create(:ssp_control, ssp_document: ssp, control_id: "AU-6", title: "Audit Review")
    end

    it "requires a token" do
      post generate_api_v1_sap_documents_path, params: { sap_document: { ssp_document_id: ssp.id } }
      expect(response).to have_http_status(:unauthorized)
    end

    it "generates a POPULATED SAP from an SSP" do
      expect {
        post generate_api_v1_sap_documents_path,
          params: { sap_document: { ssp_document_id: ssp.id, name: "FY26 Annual" } },
          headers: auth_headers
      }.to change(SapDocument, :count).by(1)

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["name"]).to eq("FY26 Annual")
      # The whole point: controls, not an empty shell.
      expect(data["controls_count"]).to eq(2)
      # #911 — controls store the canonical form; the SSP rows were seeded as
      # "AC-2" / "AU-6" and carry through as the same controls, canonically spelled.
      expect(SapDocument.find(data["id"]).sap_controls.pluck(:control_id)).to match_array(%w[ac-2 au-6])
    end

    # The between-assessments case: a boundary should be able to ask for a
    # fresh plan without the caller restating where its control basis lives.
    it "generates from a boundary alone, and attaches the result to it" do
      post generate_api_v1_sap_documents_path,
        params: { sap_document: { authorization_boundary_id: boundary.id } },
        headers: auth_headers

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["controls_count"]).to eq(2)
      expect(data["authorization_boundary_id"]).to eq(boundary.id)
    end

    it "accepts a boundary slug as well as an id" do
      post generate_api_v1_sap_documents_path,
        params: { sap_document: { authorization_boundary_id: boundary.slug } },
        headers: auth_headers

      expect(response).to have_http_status(:created)
    end

    it "restricts generation to the selected controls" do
      post generate_api_v1_sap_documents_path,
        params: { sap_document: { ssp_document_id: ssp.id, control_ids: [ "AC-2" ] } },
        headers: auth_headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["data"]["controls_count"]).to eq(1)
    end

    it "names the SAP when the caller does not" do
      post generate_api_v1_sap_documents_path,
        params: { sap_document: { ssp_document_id: ssp.id } }, headers: auth_headers

      expect(JSON.parse(response.body)["data"]["name"]).to include(boundary.name)
    end

    # Generating by ssp_document_id alone used to produce a SAP attached to
    # nothing, so the boundary still reported having no plan.
    it "attaches to the SSP's own boundary when none is named" do
      post generate_api_v1_sap_documents_path,
        params: { sap_document: { ssp_document_id: ssp.id } }, headers: auth_headers

      expect(JSON.parse(response.body)["data"]["authorization_boundary_id"]).to eq(boundary.id)
      expect(boundary.reload.sap_document).to be_present
    end

    # A SAP covering nothing is a wrong result, not a degraded one — the
    # generator returns an empty control set when given neither source, and
    # would otherwise persist that and report success.
    it "refuses when there is no control basis at all" do
      empty_boundary = create(:authorization_boundary)

      expect {
        post generate_api_v1_sap_documents_path,
          params: { sap_document: { authorization_boundary_id: empty_boundary.id } },
          headers: auth_headers
      }.not_to change(SapDocument, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to match(/no control basis/i)
    end

    # filter_controls normalises case but NOT zero-padding, so this is a
    # plausible caller mistake that used to persist an empty SAP and return 201.
    it "matches control_ids case-insensitively" do
      post generate_api_v1_sap_documents_path,
        params: { sap_document: { ssp_document_id: ssp.id, control_ids: [ "ac-2" ] } },
        headers: auth_headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["data"]["controls_count"]).to eq(1)
    end

    # ...and, since #852, padding-insensitively too.
    #
    # This spec previously asserted the OPPOSITE — that "sc-7" failed to match
    # "SC-07" and generation was therefore refused. That was pinning the bug:
    # the demo seed writes SSP controls padded while control lists are
    # unpadded, so the two shapes genuinely coexist and a caller selecting
    # "sc-7" got an empty SAP. #852 made comparison canonical, so the
    # selection now matches and the plan is generated.
    it "matches control_ids across zero padding (#852)" do
      create(:ssp_control, ssp_document: ssp, control_id: "SC-07", title: "Boundary Protection")

      post generate_api_v1_sap_documents_path,
        params: { sap_document: { ssp_document_id: ssp.id, control_ids: [ "sc-7" ] } },
        headers: auth_headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["data"]["controls_count"]).to eq(1)
      expect(SapDocument.last.sap_controls.first.control_id).to eq("sc-7")
    end

    # The empty-result guard still exists — it just no longer fires for a
    # padding difference, only for a selection that names nothing real.
    it "still refuses, and saves nothing, when the selection matches no control" do
      expect {
        post generate_api_v1_sap_documents_path,
          params: { sap_document: { ssp_document_id: ssp.id, control_ids: [ "zz-99" ] } },
          headers: auth_headers
      }.not_to change(SapDocument, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to match(/covered no controls/i)
    end

    it "leaves no orphaned SAP controls behind after that rollback" do
      expect {
        post generate_api_v1_sap_documents_path,
          params: { sap_document: { ssp_document_id: ssp.id, control_ids: [ "nope-1" ] } },
          headers: auth_headers
      }.not_to change(SapControl, :count)
    end

    it "emits a sap_document_generated audit event" do
      assert_audit_event(action: "sap_document_generated", subject_type: "SapDocument") do
        post generate_api_v1_sap_documents_path,
          params: { sap_document: { ssp_document_id: ssp.id } }, headers: auth_headers
      end
    end

    # Same shape as #851: a permitted *_id that names a record the caller
    # cannot read. An SSP carries the implementation narrative for every
    # control, and the generator copies that basis into the plan.
    describe "source scoping" do
      let(:other_boundary) { create(:authorization_boundary) }
      let!(:foreign_ssp) { create(:ssp_document, authorization_boundary: other_boundary) }
      let(:member) { create(:user) }
      let(:member_token) { ApiToken.generate!(user: member, name: "Member") }
      let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

      before do
        create(:ssp_control, ssp_document: foreign_ssp, control_id: "SC-7", title: "Boundary Protection")
        # Deliberately granted FULL write permission. The point is that source
        # scoping holds independently of whether the caller may write SAPs —
        # otherwise this test would pass for the wrong reason (a 403 from the
        # write check) and prove nothing about reading another boundary's SSP.
        allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
      end

      it "refuses to generate from an SSP the caller cannot read" do
        expect {
          post generate_api_v1_sap_documents_path,
            params: { sap_document: { ssp_document_id: foreign_ssp.id, authorization_boundary_id: boundary.id } },
            headers: member_headers
        }.not_to change(SapDocument, :count)

        expect(response).to have_http_status(:not_found)
      end

      it "still allows an admin to generate from any SSP" do
        post generate_api_v1_sap_documents_path,
          params: { sap_document: { ssp_document_id: foreign_ssp.id } }, headers: auth_headers

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe "GET /api/v1/sap_documents" do
    it "returns paginated list for admin" do
      create_list(:sap_document, 2, authorization_boundary: boundary)

      get api_v1_sap_documents_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(2)
      expect(parsed["meta"]).to include("page", "count")
    end

    context "as a boundary-scoped user" do
      let(:boundary_user) { create(:user) }
      let(:boundary_role) { create(:role, :authorization_boundary_scoped, permissions: { "sap.read" => true }) }
      let!(:user_role) { create(:user_role, user: boundary_user, role: boundary_role, authorization_boundary_id: boundary.id) }
      let(:boundary_token) { ApiToken.generate!(user: boundary_user, name: "Boundary Token") }
      let(:boundary_headers) { { "Authorization" => "Bearer #{boundary_token.plaintext_token}" } }

      it "sees only documents in their boundary" do
        create(:sap_document, authorization_boundary: boundary)
        create(:sap_document, authorization_boundary: create(:authorization_boundary))

        get api_v1_sap_documents_path, headers: boundary_headers
        parsed = JSON.parse(response.body)
        expect(parsed["data"].length).to eq(1)
      end
    end
  end

  describe "GET /api/v1/sap_documents/:id" do
    it "returns detailed document" do
      sap = create(:sap_document, authorization_boundary: boundary)

      get api_v1_sap_document_path(sap), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["id"]).to eq(sap.id)
      expect(parsed["data"]).to have_key("controls_count")
      expect(parsed["data"]).to have_key("assessment_type")
    end
  end

  describe "POST /api/v1/sap_documents" do
    it "creates a document as admin" do
      expect {
        post api_v1_sap_documents_path, params: {
          sap_document: {
            name: "New SAP",
            authorization_boundary_id: boundary.id,
            assessment_type: "initial"
          }
        }, headers: auth_headers, as: :json
      }.to change(SapDocument, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("New SAP")
    end

    it "creates an audit event" do
      expect {
        post api_v1_sap_documents_path, params: {
          sap_document: { name: "Audited SAP", authorization_boundary_id: boundary.id }
        }, headers: auth_headers, as: :json
      }.to change(AuditEvent, :count).by(1)
    end

    context "as a non-admin without write permission" do
      let(:reader_user) { create(:user) }
      let(:read_role) { create(:role, :authorization_boundary_scoped, permissions: { "sap.read" => true, "sap.write" => false }) }
      let!(:user_role) { create(:user_role, user: reader_user, role: read_role, authorization_boundary_id: boundary.id) }
      let(:reader_token) { ApiToken.generate!(user: reader_user, name: "Reader Token") }
      let(:reader_headers) { { "Authorization" => "Bearer #{reader_token.plaintext_token}" } }

      it "returns 403" do
        post api_v1_sap_documents_path, params: {
          sap_document: { name: "Denied SAP" }
        }, headers: reader_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PUT /api/v1/sap_documents/:id" do
    # #911 layer 2 — OSCAL requires `import-ssp` on an assessment plan, so the
    # reconciliation gate refuses an update until the SSP is named. The refusal
    # itself is covered below.
    let(:baseline) { create(:ssp_document) }

    it "updates a document as admin" do
      sap = create(:sap_document, authorization_boundary: boundary, ssp_document: baseline)

      put api_v1_sap_document_path(sap), params: {
        sap_document: { name: "Updated SAP", assessment_type: "annual" }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("Updated SAP")
    end

    it "emits a sap_document_updated audit event (#433 slice 5)" do
      sap = create(:sap_document, authorization_boundary: boundary, ssp_document: baseline)
      assert_audit_event(
        action: "sap_document_updated",
        subject_type: "SapDocument",
        metadata: { name: "Updated SAP" }
      ) do
        put api_v1_sap_document_path(sap), params: {
          sap_document: { name: "Updated SAP" }
        }, headers: auth_headers, as: :json
      end
    end
  end

  describe "DELETE /api/v1/sap_documents/:id" do
    it "soft-deletes the document" do
      sap = create(:sap_document, authorization_boundary: boundary)

      delete api_v1_sap_document_path(sap), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["deleted"]).to be true
      expect(SapDocument.find_by(id: sap.id)).to be_nil
      expect(SapDocument.with_deleted.find_by(id: sap.id)).to be_present
    end

    it "emits a sap_document_deleted audit event (#433 slice 5)" do
      sap = create(:sap_document, authorization_boundary: boundary)
      assert_audit_event(
        action: "sap_document_deleted",
        subject_type: "SapDocument",
        metadata: { name: sap.name }
      ) do
        delete api_v1_sap_document_path(sap), headers: auth_headers
      end
    end
  end
end
