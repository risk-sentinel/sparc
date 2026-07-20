# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Translations", type: :request do
  let(:user)         { create(:user) }
  let(:token)        { ApiToken.generate!(user: user, name: "Translation Test") }
  let(:auth_headers) { { auth_header_key => "Bearer #{token.plaintext_token}" } }
  # Shared literals extracted to avoid duplication (Sonar S1192).
  let(:json_mime)       { "application/json" }
  let(:json_ct)         { { "Content-Type" => json_mime } }
  let(:auth_header_key) { "Authorization" }
  let(:poam_root_key)   { "plan-of-action-and-milestones" }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  # Stub the HdfOscalTranslationService so we don't need the real binary
  # in the test environment. The service is exercised against a doubled
  # HdfRunner in spec/services/hdf_oscal_translation_service_spec.rb.
  let(:translation_service) { instance_double(HdfOscalTranslationService) }
  before { allow(HdfOscalTranslationService).to receive(:new).and_return(translation_service) }

  let(:hdf_payload)        { { "version" => "1.0", "profiles" => [] }.to_json }
  let(:poam_payload)       { { poam_root_key => { "uuid" => "x" } }.to_json }
  let(:amendments_payload) { { "overrides" => [ { "type" => "poam", "controlId" => "AC-2" } ] }.to_json }

  describe "authentication" do
    it "401s without a token on every endpoint" do
      [
        api_v1_sar_from_hdf_path,
        api_v1_poam_from_hdf_path,
        api_v1_poam_from_amendments_path,
        api_v1_amendments_from_oscal_poam_path
      ].each do |path|
        post path, params: hdf_payload, headers: json_ct
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/oscal/sar_from_hdf" do
    let(:sar_doc) { { "assessment-results" => { "uuid" => "abc-123" } } }

    it "translates a raw JSON body to OSCAL SAR" do
      expect(translation_service).to receive(:hdf_to_oscal_sar)
        .with(an_instance_of(String), boundary: nil)
        .and_return(sar_doc)

      post api_v1_sar_from_hdf_path,
           params: hdf_payload,
           headers: auth_headers.merge(json_ct)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(sar_doc)
    end

    it "translates multipart upload" do
      expect(translation_service).to receive(:hdf_to_oscal_sar)
        .with(an_instance_of(String), boundary: nil)
        .and_return(sar_doc)

      file = Rack::Test::UploadedFile.new(
        StringIO.new(hdf_payload),
        json_mime,
        original_filename: "scan.hdf.json"
      )
      post api_v1_sar_from_hdf_path,
           params: { file: file },
           headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(sar_doc)
    end

    it "audits successful translation" do
      allow(translation_service).to receive(:hdf_to_oscal_sar).and_return(sar_doc)
      expect {
        post api_v1_sar_from_hdf_path,
             params: hdf_payload,
             headers: auth_headers.merge(json_ct)
      }.to change { AuditEvent.where(action: "translation_hdf_to_oscal_sar").count }.by(1)
    end

    it "400s when neither :file nor a body is provided" do
      post api_v1_sar_from_hdf_path, headers: auth_headers
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to match(/No payload/i)
    end

    it "passes the boundary through when authorization_boundary_id query param is provided (#449 L4)" do
      boundary = create(:authorization_boundary)
      admin = create(:user, :admin)
      admin_token = ApiToken.generate!(user: admin, name: "L4 admin")
      admin_headers = { auth_header_key => "Bearer #{admin_token.plaintext_token}" }

      expect(translation_service).to receive(:hdf_to_oscal_sar)
        .with(an_instance_of(String), boundary: boundary)
        .and_return(sar_doc)

      post "#{api_v1_sar_from_hdf_path}?authorization_boundary_id=#{boundary.id}",
           params: hdf_payload,
           headers: admin_headers.merge(json_ct)
      expect(response).to have_http_status(:ok)
    end

    it "403s on boundary use without evidence.read" do
      boundary = create(:authorization_boundary)
      regular_user = create(:user)
      regular_token = ApiToken.generate!(user: regular_user, name: "L4 regular")
      regular_headers = { auth_header_key => "Bearer #{regular_token.plaintext_token}" }

      post "#{api_v1_sar_from_hdf_path}?authorization_boundary_id=#{boundary.id}",
           params: hdf_payload,
           headers: regular_headers.merge(json_ct)
      expect(response).to have_http_status(:forbidden)
    end

    it "422s when the runner raises HdfRunner::Error" do
      allow(translation_service).to receive(:hdf_to_oscal_sar).and_raise(
        HdfRunner::Error.new(
          "hdf convert failed (exit 2): malformed input",
          command: "hdf convert ...",
          exit_code: 2,
          stderr: "malformed input at line 5\n"
        )
      )
      post api_v1_sar_from_hdf_path,
           params: hdf_payload,
           headers: auth_headers.merge(json_ct)
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/translation failed/i)
      expect(body["stderr"]).to include("malformed input")
    end
  end

  describe "POST /api/v1/oscal/poam_from_hdf" do
    let(:poam_doc) { { poam_root_key => { "uuid" => "p-1" } } }

    it "translates a raw JSON body to OSCAL POAM" do
      expect(translation_service).to receive(:hdf_to_oscal_poam)
        .with(an_instance_of(String), boundary: nil)
        .and_return(poam_doc)
      post api_v1_poam_from_hdf_path,
           params: hdf_payload,
           headers: auth_headers.merge(json_ct)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(poam_doc)
    end

    it "audits the HDF→OSCAL POAM translation" do
      allow(translation_service).to receive(:hdf_to_oscal_poam).and_return(poam_doc)
      expect {
        post api_v1_poam_from_hdf_path,
             params: hdf_payload,
             headers: auth_headers.merge(json_ct)
      }.to change { AuditEvent.where(action: "translation_hdf_to_oscal_poam").count }.by(1)
    end

    # hdf-cli 3.2.0 removed the hdf→oscal-poam converter (upstream
    # mitre/hdf-libs#104). When the bundled CLI lacks the path it raises
    # "no converter found", which the controller maps to 501 Not Implemented
    # (not a 422) so callers can distinguish "unsupported path" from "bad
    # input". The forward-compat happy-path specs above keep passing once a
    # future hdf-cli restores the converter. See #648.
    it "501s when the bundled hdf-cli lacks the converter (no converter found)" do
      allow(translation_service).to receive(:hdf_to_oscal_poam).and_raise(
        HdfRunner::Error.new(
          "hdf convert failed (exit 1): no converter found for: hdf → oscal-poam",
          command: "hdf convert ...",
          exit_code: 1,
          stderr: "no converter found for: hdf → oscal-poam\n"
        )
      )
      post api_v1_poam_from_hdf_path,
           params: hdf_payload,
           headers: auth_headers.merge(json_ct)
      expect(response).to have_http_status(:not_implemented)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/not available in the bundled hdf-cli/i)
      expect(body["note"]).to include("mitre/hdf-libs")
    end
  end

  describe "POST /api/v1/oscal/poam_from_amendments" do
    let(:poam_doc) { { poam_root_key => { "uuid" => "p-amd-1" } } }

    it "translates a raw JSON body (HDF amendments) to OSCAL POAM" do
      expect(translation_service).to receive(:oscal_poam_from_hdf_amendments)
        .with(an_instance_of(String), boundary: nil)
        .and_return(poam_doc)
      post api_v1_poam_from_amendments_path,
           params: amendments_payload,
           headers: auth_headers.merge(json_ct)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(poam_doc)
    end

    it "audits the amendments→OSCAL POAM translation" do
      allow(translation_service).to receive(:oscal_poam_from_hdf_amendments).and_return(poam_doc)
      expect {
        post api_v1_poam_from_amendments_path,
             params: amendments_payload,
             headers: auth_headers.merge(json_ct)
      }.to change { AuditEvent.where(action: "translation_hdf_amendments_to_oscal_poam").count }.by(1)
    end
  end

  describe "POST /api/v1/hdf/amendments_from_oscal_poam" do
    let(:amendments) { { "overrides" => [ { "type" => "poam", "controlId" => "AC-2" } ] } }

    it "translates a raw JSON body to HDF amendments" do
      expect(translation_service).to receive(:oscal_poam_to_hdf_amendments).and_return(amendments)
      post api_v1_amendments_from_oscal_poam_path,
           params: poam_payload,
           headers: auth_headers.merge(json_ct)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(amendments)
    end

    it "audits the OSCAL POAM→amendments translation" do
      allow(translation_service).to receive(:oscal_poam_to_hdf_amendments).and_return(amendments)
      expect {
        post api_v1_amendments_from_oscal_poam_path,
             params: poam_payload,
             headers: auth_headers.merge(json_ct)
      }.to change { AuditEvent.where(action: "translation_oscal_poam_to_hdf_amendments").count }.by(1)
    end

    # #764 — hdf-cli 3.4.1 stopped fabricating expiry dates for POA&M items
    # with no derivable deadline and fails loud instead. 3.3.2 exited 0 by
    # inventing conversion-time + 1 year, so this is a correction, but it is a
    # NEW exit-1 path whose fix lies entirely in the caller's input. It must
    # not read as a generic bridge failure.
    it "422s with an actionable message when the POA&M carries no deadline" do
      allow(translation_service).to receive(:oscal_poam_to_hdf_amendments).and_raise(
        HdfRunner::Error.new(
          'hdf convert failed (exit 1): conversion failed: oscal-poam conversion failed: ' \
          'poam-item "Remediate finding": no related risk carries a usable deadline; ' \
          "a POA&M requires a time commitment",
          command: "hdf convert ...",
          exit_code: 1,
          stderr: "no related risk carries a usable deadline\n"
        )
      )
      post api_v1_amendments_from_oscal_poam_path,
           params: poam_payload,
           headers: auth_headers.merge(json_ct)

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("POA&M is missing a remediation deadline")
      expect(body["note"]).to include("risks[].deadline")
    end
  end
end
