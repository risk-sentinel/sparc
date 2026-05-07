# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Translations", type: :request do
  let(:user)         { create(:user) }
  let(:token)        { ApiToken.generate!(user: user, name: "Translation Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  # Stub the HdfOscalTranslationService so we don't need the real binary
  # in the test environment. The service is exercised against a doubled
  # HdfRunner in spec/services/hdf_oscal_translation_service_spec.rb.
  let(:translation_service) { instance_double(HdfOscalTranslationService) }
  before { allow(HdfOscalTranslationService).to receive(:new).and_return(translation_service) }

  let(:hdf_payload)  { { "version" => "1.0", "profiles" => [] }.to_json }
  let(:poam_payload) { { "plan-of-action-and-milestones" => { "uuid" => "x" } }.to_json }

  describe "authentication" do
    it "401s without a token on every endpoint" do
      [
        api_v1_sar_from_hdf_path,
        api_v1_poam_from_hdf_path,
        api_v1_amendments_from_oscal_poam_path
      ].each do |path|
        post path, params: hdf_payload, headers: { "Content-Type" => "application/json" }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/oscal/sar_from_hdf" do
    let(:sar_doc) { { "assessment-results" => { "uuid" => "abc-123" } } }

    it "translates raw JSON body" do
      expect(translation_service).to receive(:hdf_to_oscal_sar)
        .with(an_instance_of(String), boundary: nil)
        .and_return(sar_doc)

      post api_v1_sar_from_hdf_path,
           params: hdf_payload,
           headers: auth_headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(sar_doc)
    end

    it "translates multipart upload" do
      expect(translation_service).to receive(:hdf_to_oscal_sar)
        .with(an_instance_of(String), boundary: nil)
        .and_return(sar_doc)

      file = Rack::Test::UploadedFile.new(
        StringIO.new(hdf_payload),
        "application/json",
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
             headers: auth_headers.merge("Content-Type" => "application/json")
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
      admin_headers = { "Authorization" => "Bearer #{admin_token.plaintext_token}" }

      expect(translation_service).to receive(:hdf_to_oscal_sar)
        .with(an_instance_of(String), boundary: boundary)
        .and_return(sar_doc)

      post "#{api_v1_sar_from_hdf_path}?authorization_boundary_id=#{boundary.id}",
           params: hdf_payload,
           headers: admin_headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:ok)
    end

    it "403s on boundary use without evidence.read" do
      boundary = create(:authorization_boundary)
      regular_user = create(:user)
      regular_token = ApiToken.generate!(user: regular_user, name: "L4 regular")
      regular_headers = { "Authorization" => "Bearer #{regular_token.plaintext_token}" }

      post "#{api_v1_sar_from_hdf_path}?authorization_boundary_id=#{boundary.id}",
           params: hdf_payload,
           headers: regular_headers.merge("Content-Type" => "application/json")
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
           headers: auth_headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/translation failed/i)
      expect(body["stderr"]).to include("malformed input")
    end
  end

  describe "POST /api/v1/oscal/poam_from_hdf" do
    let(:poam_doc) { { "plan-of-action-and-milestones" => { "uuid" => "p-1" } } }

    it "translates raw JSON body" do
      expect(translation_service).to receive(:hdf_to_oscal_poam)
        .with(an_instance_of(String), boundary: nil)
        .and_return(poam_doc)
      post api_v1_poam_from_hdf_path,
           params: hdf_payload,
           headers: auth_headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(poam_doc)
    end

    it "audits the translation" do
      allow(translation_service).to receive(:hdf_to_oscal_poam).and_return(poam_doc)
      expect {
        post api_v1_poam_from_hdf_path,
             params: hdf_payload,
             headers: auth_headers.merge("Content-Type" => "application/json")
      }.to change { AuditEvent.where(action: "translation_hdf_to_oscal_poam").count }.by(1)
    end
  end

  describe "POST /api/v1/hdf/amendments_from_oscal_poam" do
    let(:amendments) { { "overrides" => [ { "type" => "poam", "controlId" => "AC-2" } ] } }

    it "translates raw JSON body" do
      expect(translation_service).to receive(:oscal_poam_to_hdf_amendments).and_return(amendments)
      post api_v1_amendments_from_oscal_poam_path,
           params: poam_payload,
           headers: auth_headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(amendments)
    end

    it "audits the translation" do
      allow(translation_service).to receive(:oscal_poam_to_hdf_amendments).and_return(amendments)
      expect {
        post api_v1_amendments_from_oscal_poam_path,
             params: poam_payload,
             headers: auth_headers.merge("Content-Type" => "application/json")
      }.to change { AuditEvent.where(action: "translation_oscal_poam_to_hdf_amendments").count }.by(1)
    end
  end
end
