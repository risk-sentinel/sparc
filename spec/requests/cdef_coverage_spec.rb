# frozen_string_literal: true

require "rails_helper"

# #904 — the coverage wizard on the web surface.
RSpec.describe "CdefCoverage", type: :request do
  let(:user) { create(:user, :admin) }

  before do
    sign_in_as(user)
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  WEB_STATE_SECRET = "WebPlaintextSecret-must-not-be-stored" # rubocop:disable Lint/ConstantDefinitionInBlock

  def state_file(types, filename: "prod.tfstate")
    body = {
      "version" => 4,
      "resources" => types.map do |type|
        { "mode" => "managed", "type" => type, "name" => "x",
          "instances" => [ { "attributes" => { "password" => WEB_STATE_SECRET } } ] }
      end
    }
    Rack::Test::UploadedFile.new(StringIO.new(JSON.generate(body)), "application/json",
                                 original_filename: filename)
  end

  describe "GET /cdef_coverage/new" do
    it "tells the operator what happens to their state file before they choose one" do
      get new_cdef_coverage_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("not stored")
      expect(response.body).to include("plaintext secrets")
    end
  end

  describe "POST /cdef_coverage/analyze" do
    it "renders verdicts and persists nothing" do
      create(:cdef_document, import_metadata: { "source_type" => "aws_labs",
                                                "source_path" => "component-definitions/ecs.oscal.json" })

      expect {
        post analyze_cdef_coverage_index_path,
             params: { files: [ state_file(%w[aws_ecs_service aws_guardduty_detector]) ] }
      }.not_to change(CdefCoverageRun, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Adopt AWS Labs CDEF")
      expect(response.body).to include("Needs a CDEF")
      expect(response.body).to include("guardduty")
    end

    it "shows no attribute values on the page" do
      post analyze_cdef_coverage_index_path, params: { files: [ state_file(%w[aws_db_instance]) ] }

      expect(response.body).not_to include(WEB_STATE_SECRET)
      expect(response.body).to include("aws_db_instance")
    end

    it "re-renders the form with the offending filename when a file is not Terraform" do
      bad = Rack::Test::UploadedFile.new(StringIO.new(%({"hello":"world"})), "application/json",
                                         original_filename: "notes.json")

      post analyze_cdef_coverage_index_path, params: { files: [ bad ] }

      expect(response).to have_http_status(:unprocessable_entity)
      # Asserted on the body, not on flash[] — a flash key that is not in
      # FLASH_CLASSES renders nowhere at all, silently.
      expect(response.body).to include("notes.json")
    end
  end

  describe "POST /cdef_coverage" do
    def analysis_token(types = %w[aws_guardduty_detector])
      post analyze_cdef_coverage_index_path, params: { files: [ state_file(types) ] }
      response.body[/name="report_token" id="report_token" value="([^"]+)"/, 1] ||
        response.body[/name="report_token"[^>]*value="([^"]+)"/, 1]
    end

    it "saves the analysis the report screen carried" do
      token = analysis_token
      boundary = create(:authorization_boundary)

      expect {
        post cdef_coverage_index_path, params: { report_token: token,
                                                 authorization_boundary_id: boundary.id }
      }.to change(CdefCoverageRun, :count).by(1)

      run = CdefCoverageRun.last
      expect(run.authorization_boundary).to eq(boundary)
      expect(run.created_by_user).to eq(user)
      expect(run.needs_custom_count).to eq(1)
      expect(response).to redirect_to(cdef_coverage_path(run))
    end

    it "persists no attribute values" do
      token = analysis_token(%w[aws_db_instance])
      post cdef_coverage_index_path, params: { report_token: token }

      run = CdefCoverageRun.last
      serialised = { run: run.attributes, results: run.cdef_coverage_results.map(&:attributes) }.to_json
      expect(serialised).not_to include(WEB_STATE_SECRET)
      expect(serialised).to include("aws_db_instance")
    end

    # The signature is what makes it safe to round-trip a compliance artifact
    # through the browser.
    it "refuses a tampered token rather than saving a forged analysis" do
      token = analysis_token

      expect {
        post cdef_coverage_index_path, params: { report_token: "#{token}x" }
      }.not_to change(CdefCoverageRun, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses a missing token" do
      expect {
        post cdef_coverage_index_path, params: {}
      }.not_to change(CdefCoverageRun, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /cdef_coverage/:id" do
    it "shows the saved verdicts and the file checksums" do
      run = create(:cdef_coverage_run)
      run.cdef_coverage_results.create!(service_key: "guardduty", verdict: "needs_custom",
                                        resource_count: 1, resource_types: [ "aws_guardduty_detector" ])

      get cdef_coverage_path(run)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("guardduty")
      expect(response.body).to include("Needs a CDEF")
      expect(response.body).to include("not stored")
    end
  end

  describe "GET /cdef_coverage" do
    it "lists saved analyses" do
      create(:cdef_coverage_run)
      get cdef_coverage_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("CDEF Coverage Analyses")
    end
  end

  describe "the boundary entry point" do
    it "offers the wizard from the boundary screen, pre-attached to it" do
      boundary = create(:authorization_boundary)

      get authorization_boundary_path(boundary)

      expect(response.body).to include("CDEF Coverage")
      expect(response.body).to include(new_cdef_coverage_path(authorization_boundary_id: boundary.id))
    end
  end
end
