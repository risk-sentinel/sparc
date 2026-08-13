# frozen_string_literal: true

require "rails_helper"

# #904 — the coverage API.
#
# The security expectations here are the ones that matter most: a .tfstate
# carries plaintext secrets, and the whole design depends on the upload being
# read and dropped. "We don't store it" is asserted, not asserted-in-a-comment.
RSpec.describe "Api::V1::CdefCoverage", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  STATE_SECRET = "PlaintextMasterPassword-must-not-be-stored" # rubocop:disable Lint/ConstantDefinitionInBlock

  def state_file(types, filename: "prod.tfstate")
    body = {
      "version" => 4,
      "resources" => types.map do |type|
        { "mode" => "managed", "type" => type, "name" => "x",
          "instances" => [ { "attributes" => { "password" => STATE_SECRET,
                                               "account_id" => "123456789012" } } ] }
      end
    }
    Rack::Test::UploadedFile.new(StringIO.new(JSON.generate(body)), "application/json",
                                 original_filename: filename)
  end

  describe "POST /api/v1/cdef_coverage/analyze" do
    it "returns verdicts without persisting anything" do
      create(:cdef_document, import_metadata: { "source_type" => "aws_labs",
                                                "source_path" => "component-definitions/ecs.oscal.json" })

      expect {
        post api_v1_cdef_coverage_analyze_path,
             params: { files: [ state_file(%w[aws_ecs_service aws_guardduty_detector]) ] },
             headers: admin_headers
      }.not_to change(CdefCoverageRun, :count)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      verdicts = data["findings"].to_h { |f| [ f["service"], f["verdict"] ] }
      expect(verdicts).to eq("ecs" => "adopt", "guardduty" => "needs_custom")
      expect(data["counts"]).to include("needs_custom" => 1)
    end

    it "accepts several files as one boundary" do
      post api_v1_cdef_coverage_analyze_path,
           params: { files: [ state_file(%w[aws_ecs_service], filename: "ecs.tfstate"),
                              state_file(%w[aws_config_rule], filename: "config.tfstate") ] },
           headers: admin_headers

      data = JSON.parse(response.body)["data"]
      expect(data["findings"].map { |f| f["service"] }).to contain_exactly("config", "ecs")
      expect(data["sources"].map { |s| s["filename"] }).to contain_exactly("ecs.tfstate", "config.tfstate")
    end

    it "reports an unrecognised resource as a gap under an inferred key" do
      post api_v1_cdef_coverage_analyze_path,
           params: { files: [ state_file(%w[azurerm_storage_account]) ] }, headers: admin_headers

      finding = JSON.parse(response.body)["data"]["findings"].sole
      expect(finding).to include("service" => "azurerm:storage", "verdict" => "needs_custom",
                                 "inferred" => true)
    end

    it "422s with the offending filename when a file is not Terraform" do
      bad = Rack::Test::UploadedFile.new(StringIO.new(%({"hello":"world"})), "application/json",
                                         original_filename: "notes.json")
      post api_v1_cdef_coverage_analyze_path, params: { files: [ bad ] }, headers: admin_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/notes\.json/)
    end

    # ── The reason this feature can accept a state file at all ────────────
    describe "sensitive content" do
      it "stores no Active Storage blob for the upload" do
        expect {
          post api_v1_cdef_coverage_analyze_path,
               params: { files: [ state_file(%w[aws_db_instance]) ] }, headers: admin_headers
        }.not_to change(ActiveStorage::Blob, :count)
      end

      it "returns no attribute values in the response" do
        post api_v1_cdef_coverage_analyze_path,
             params: { files: [ state_file(%w[aws_db_instance]) ] }, headers: admin_headers

        expect(response.body).not_to include(STATE_SECRET)
        expect(response.body).not_to include("123456789012")
        expect(response.body).to include("aws_db_instance")
      end

      it "writes no attribute values into the audit record" do
        post api_v1_cdef_coverage_analyze_path,
             params: { files: [ state_file(%w[aws_db_instance]) ] }, headers: admin_headers

        event = AuditEvent.where(action: "cdef_coverage_analyzed").order(:id).last
        expect(event).to be_present
        expect(event.metadata.to_json).not_to include(STATE_SECRET)
      end
    end
  end

  describe "POST /api/v1/cdef_coverage/runs" do
    it "saves the derived report and attaches it to a boundary" do
      boundary = create(:authorization_boundary)

      expect {
        post api_v1_cdef_coverage_runs_path,
             params: { files: [ state_file(%w[aws_guardduty_detector]) ],
                       authorization_boundary_id: boundary.id },
             headers: admin_headers
      }.to change(CdefCoverageRun, :count).by(1)

      expect(response).to have_http_status(:created)
      run = CdefCoverageRun.last
      expect(run.authorization_boundary).to eq(boundary)
      expect(run.created_by_user).to eq(admin)
      expect(run.needs_custom_count).to eq(1)
    end

    it "saves an unattached run when no boundary is given" do
      post api_v1_cdef_coverage_runs_path,
           params: { files: [ state_file(%w[aws_s3_bucket]) ] }, headers: admin_headers

      expect(response).to have_http_status(:created)
      expect(CdefCoverageRun.last.authorization_boundary_id).to be_nil
    end

    it "persists resource type names but no attribute values" do
      post api_v1_cdef_coverage_runs_path,
           params: { files: [ state_file(%w[aws_db_instance]) ] }, headers: admin_headers

      run = CdefCoverageRun.last
      serialised = { run: run.attributes, results: run.cdef_coverage_results.map(&:attributes) }.to_json
      expect(serialised).not_to include(STATE_SECRET)
      expect(serialised).not_to include("123456789012")
      expect(serialised).to include("aws_db_instance")
    end

    it "records each source file by name and digest only" do
      post api_v1_cdef_coverage_runs_path,
           params: { files: [ state_file(%w[aws_s3_bucket], filename: "prod.tfstate") ] },
           headers: admin_headers

      source = CdefCoverageRun.last.source_files.sole
      expect(source["filename"]).to eq("prod.tfstate")
      expect(source["digest"]).to match(/\A[0-9a-f]{64}\z/)
      expect(source.keys).to contain_exactly("filename", "digest", "format", "resource_count")
    end
  end

  describe "authorization" do
    before { allow_any_instance_of(User).to receive(:has_permission?).and_return(false) }

    it "403s analyze without cdef.read" do
      post api_v1_cdef_coverage_analyze_path,
           params: { files: [ state_file(%w[aws_s3_bucket]) ] }, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "403s saving a run without cdef.write" do
      allow_any_instance_of(User).to receive(:has_permission?).with("cdef.read", any_args).and_return(true)

      post api_v1_cdef_coverage_runs_path,
           params: { files: [ state_file(%w[aws_s3_bucket]) ] }, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "401s without a token" do
      post api_v1_cdef_coverage_analyze_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/cdef_coverage/runs" do
    it "lists runs for admin, newest first" do
      older = create(:cdef_coverage_run, analyzed_at: 2.days.ago)
      newer = create(:cdef_coverage_run, analyzed_at: 1.hour.ago)

      get api_v1_cdef_coverage_runs_path, headers: admin_headers

      expect(JSON.parse(response.body)["data"].map { |r| r["id"] }).to eq([ newer.id, older.id ])
    end

    it "scopes a non-admin to their boundaries plus unattached runs" do
      allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
      mine = create(:authorization_boundary)
      theirs = create(:authorization_boundary)
      create(:user_role, user: member, role: create(:role, :authorization_boundary_scoped),
             authorization_boundary_id: mine.id)

      visible = create(:cdef_coverage_run, authorization_boundary: mine)
      global  = create(:cdef_coverage_run, authorization_boundary: nil)
      create(:cdef_coverage_run, authorization_boundary: theirs)

      get api_v1_cdef_coverage_runs_path, headers: member_headers

      expect(JSON.parse(response.body)["data"].map { |r| r["id"] }).to contain_exactly(visible.id, global.id)
    end
  end

  describe "GET /api/v1/cdef_coverage/runs/:id" do
    it "returns the findings and unmapped types" do
      run = create(:cdef_coverage_run)
      run.cdef_coverage_results.create!(service_key: "guardduty", verdict: "needs_custom",
                                        resource_count: 1, resource_types: [ "aws_guardduty_detector" ])

      get api_v1_cdef_coverage_run_path(run), headers: admin_headers

      data = JSON.parse(response.body)["data"]
      expect(data["findings"].sole).to include("service" => "guardduty",
                                               "verdict_label" => "Needs a CDEF")
    end
  end

  describe "DELETE /api/v1/cdef_coverage/runs/:id" do
    it "removes the run and audits it" do
      run = create(:cdef_coverage_run)

      expect {
        delete api_v1_cdef_coverage_run_path(run), headers: admin_headers
      }.to change(CdefCoverageRun, :count).by(-1)

      expect(AuditEvent.where(action: "cdef_coverage_run_deleted")).to exist
    end
  end
end
