# frozen_string_literal: true

require "rails_helper"

# Issue #697 (P0) — bulk ODP (OSCAL set-parameter) file import for a
# baseline/profile: preview (non-destructive diff) → confirm (atomic apply with
# partial-success). Multipart :file in JSON / YAML / XML.
RSpec.describe "Api::V1::BaselineParameters ODP import (#697)", type: :request do
  let(:admin)        { create(:user, :admin) }
  let(:api_token)    { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:control_with_params) do
    create(:catalog_control, :with_params, control_family: family, control_id: "ac-1",
      title: "Policy and Procedures")
  end
  let!(:control_with_select) do
    create(:catalog_control, :with_select_param, control_family: family, control_id: "ac-2",
      title: "Account Management")
  end
  let(:profile) { create(:profile_document, control_catalog: catalog) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def upload(name, type)
    Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/odp", name), type
    )
  end

  def preview_path = import_preview_api_v1_profile_document_parameters_path(profile)
  def confirm_path = import_confirm_api_v1_profile_document_parameters_path(profile)

  describe "authentication" do
    it "returns 401 without a token" do
      post preview_path, params: { file: upload("sample_odp.json", "application/json") }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST .../parameters/import/preview" do
    it "returns a non-destructive diff and writes nothing" do
      expect {
        post preview_path,
          params: { file: upload("sample_odp.json", "application/json") }, headers: auth_headers
      }.not_to change(ProfileControlField, :count)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["stats"]["total"]).to eq(3)
      expect(data["stats"]["changes"]).to eq(3) # two params + one selection, all from empty

      param_row = data["rows"].find { |r| r["param_id"] == "ac-1_prm_1" }
      expect(param_row["status"]).to eq("change")
      expect(param_row["new_value"]).to eq("ISSO and System Administrators")
      expect(param_row["current_value"]).to eq("")
    end

    it "parses XML and YAML equivalently" do
      %w[sample_odp.xml sample_odp.yaml].each do |name|
        post preview_path, params: { file: upload(name, "text/plain") }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["data"]["stats"]["total"]).to eq(3)
      end
    end

    it "flags unknown parameter ids" do
      file = Tempfile.new([ "odp", ".json" ])
      file.write({ parameters: [ { param_id: "zz-9_prm_1", value: "x" } ] }.to_json)
      file.rewind
      post preview_path,
        params: { file: Rack::Test::UploadedFile.new(file.path, "application/json") },
        headers: auth_headers

      data = JSON.parse(response.body)["data"]
      expect(data["stats"]["unknown"]).to eq(1)
      expect(data["rows"].first["status"]).to eq("unknown")
    ensure
      file.close!
    end

    it "flags selection values that aren't an allowed choice" do
      file = Tempfile.new([ "odp", ".json" ])
      file.write({ selections: [ { select_id: "ac-2_prm_1", selected: [ "teleports" ] } ] }.to_json)
      file.rewind
      post preview_path,
        params: { file: Rack::Test::UploadedFile.new(file.path, "application/json") },
        headers: auth_headers

      data = JSON.parse(response.body)["data"]
      expect(data["stats"]["invalid"]).to eq(1)
      expect(data["rows"].first["message"]).to include("teleports")
    ensure
      file.close!
    end

    it "422s when no file is provided" do
      post preview_path, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("multipart")
    end
  end

  describe "POST .../parameters/import/confirm" do
    it "applies the parsed values and reports the summary" do
      expect {
        post confirm_path,
          params: { file: upload("sample_odp.json", "application/json") }, headers: auth_headers
      }.to change(ProfileControlField, :count).by(3)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["parameters_updated"]).to eq(2)
      expect(data["selections_updated"]).to eq(1)

      field = ProfileControlField.find_by(field_name: "parameter:ac-1_prm_1")
      expect(field.field_value).to eq("ISSO and System Administrators")
    end

    it "audits the import" do
      expect {
        post confirm_path,
          params: { file: upload("sample_odp.xml", "application/xml") }, headers: auth_headers
      }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.order(:created_at).last
      expect(event.metadata["action"]).to eq("odp_file_import")
    end

    it "does not persist a selection value outside the allowed choices" do
      file = Tempfile.new([ "odp", ".json" ])
      file.write({ selections: [ { select_id: "ac-2_prm_1", selected: [ "teleports" ] } ] }.to_json)
      file.rewind
      post confirm_path,
        params: { file: Rack::Test::UploadedFile.new(file.path, "application/json") },
        headers: auth_headers

      expect(ProfileControlField.find_by(field_name: "parameter:ac-2_prm_1")).to be_nil
    ensure
      file.close!
    end

    it "422s when nothing could be applied (all unknown ids)" do
      file = Tempfile.new([ "odp", ".json" ])
      file.write({ parameters: [ { param_id: "zz-9_prm_1", value: "x" } ] }.to_json)
      file.rewind
      post confirm_path,
        params: { file: Rack::Test::UploadedFile.new(file.path, "application/json") },
        headers: auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
    ensure
      file.close!
    end
  end
end
