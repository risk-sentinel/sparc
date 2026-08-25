# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::BaselineParameters", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  let(:catalog) { create(:control_catalog) }
  let(:family) { create(:control_family, control_catalog: catalog, code: "AC") }
  let(:other_family) { create(:control_family, control_catalog: catalog, code: "AU") }
  let!(:control_with_params) do
    create(:catalog_control, :with_params,
      control_family: family,
      control_id: "ac-1",
      title: "Policy and Procedures")
  end
  let!(:control_with_select) do
    create(:catalog_control, :with_select_param,
      control_family: family,
      control_id: "ac-2",
      title: "Account Management")
  end
  let(:profile) { create(:profile_document, control_catalog: catalog) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_profile_document_parameters_path(profile)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/profile_documents/:id/parameters" do
    it "returns parameter schema" do
      get api_v1_profile_document_parameters_path(profile), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["baseline"]).to eq(profile.name)
      expect(parsed["data"]["parameters"]).to be_an(Array)
      expect(parsed["data"]["selections"]).to be_an(Array)
      expect(parsed["data"]["parameters"].length).to eq(2)
      expect(parsed["data"]["selections"].length).to eq(1)
    end

    it "includes current values from profile_control_fields" do
      pc = create(:profile_control, profile_document: profile, control_id: "ac-1")
      pc.profile_control_fields.create!(
        field_name: "parameter:ac-1_prm_1",
        field_value: "System Admins"
      )

      get api_v1_profile_document_parameters_path(profile), headers: auth_headers
      parsed = JSON.parse(response.body)
      param = parsed["data"]["parameters"].find { |p| p["param_id"] == "ac-1_prm_1" }
      expect(param["current_value"]).to eq("System Admins")
    end

    it "filters by family" do
      create(:catalog_control, :with_params,
        control_family: other_family,
        control_id: "au-1",
        title: "Audit Policy")

      get api_v1_profile_document_parameters_path(profile),
        params: { family: family.code }, headers: auth_headers
      parsed = JSON.parse(response.body)
      control_ids = parsed["data"]["parameters"].map { |p| p["control_id"] }
      expect(control_ids).to all(start_with(family.code.downcase))
    end
  end

  describe "PUT /api/v1/profile_documents/:id/parameters" do
    before do
      create(:profile_control, profile_document: profile, control_id: "ac-1")
    end

    it "updates parameters and returns summary" do
      put api_v1_profile_document_parameters_path(profile), params: {
        parameters: [
          { param_id: "ac-1_prm_1", value: "ISSO" }
        ]
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["status"]).to eq("updated")
      expect(parsed["data"]["parameters_updated"]).to eq(1)
    end

    it "creates an audit event" do
      expect {
        put api_v1_profile_document_parameters_path(profile), params: {
          parameters: [
            { param_id: "ac-1_prm_1", value: "ISSO" }
          ]
        }, headers: auth_headers, as: :json
      }.to change(AuditEvent, :count).by(1)
    end

    # ── #994: a 200 that changed nothing is not a success ──────────────────
    #
    # Every example below reproduces a payload that previously answered
    # **200 with `parameters_updated: 0, selections_updated: 0` and an empty
    # `validation_errors`** — the caller told the operation succeeded while the
    # request was never parsed at all. Each asserts BOTH halves: the refusal,
    # and that nothing was written.
    # ── #1008: published is read-only, and it was not enforced ────────────
    #
    # `profiles.write` answers "may this caller edit profiles". Whether THIS
    # profile is still editable is a different question, and only the first was
    # ever asked — so a published baseline's ODPs could be rewritten through the
    # API, 200, with the change persisting. Both directions are asserted here
    # because an allow-leg-only test passes against an endpoint with no guard at
    # all, which is how #919 and #974 were found.
    describe "editing a published profile" do
      let(:published_profile) do
        create(:profile_document, control_catalog: catalog, lifecycle_status: "published")
      end
      let(:draft_profile) do
        create(:profile_document, control_catalog: catalog, lifecycle_status: "in_progress")
      end

      it "refuses the update and names the reason" do
        create(:profile_control, profile_document: published_profile, control_id: "ac-1")

        put api_v1_profile_document_parameters_path(published_profile),
          params: { parameters: [ { param_id: "ac-1_prm_1", value: "ISSO" } ] },
          headers: auth_headers,
          as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to match(/published/i)
        expect(response.parsed_body["error"]).to match(/duplicate/i)
      end

      it "leaves the value unchanged after refusing" do
        pc = create(:profile_control, profile_document: published_profile, control_id: "ac-1")
        pc.profile_control_fields.create!(field_name: "parameter:ac-1_prm_1", field_value: "ORIGINAL")

        put api_v1_profile_document_parameters_path(published_profile),
          params: { parameters: [ { param_id: "ac-1_prm_1", value: "REWRITTEN" } ] },
          headers: auth_headers,
          as: :json

        expect(pc.profile_control_fields.find_by(field_name: "parameter:ac-1_prm_1").reload.field_value)
          .to eq("ORIGINAL")
      end

      it "still allows the update on a draft profile" do
        create(:profile_control, profile_document: draft_profile, control_id: "ac-1")

        put api_v1_profile_document_parameters_path(draft_profile),
          params: { parameters: [ { param_id: "ac-1_prm_1", value: "ISSO" } ] },
          headers: auth_headers,
          as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("data", "parameters_updated")).to eq(1)
      end

      it "still allows an import PREVIEW on a published profile, which writes nothing" do
        get api_v1_profile_document_parameters_path(published_profile), headers: auth_headers

        expect(response).to have_http_status(:ok)
      end
    end

    describe "a payload the endpoint cannot parse (#994)" do
      let(:field_names) do
        ProfileControlField.joins(:profile_control)
                           .where(profile_controls: { profile_document_id: profile.id })
                           .pluck(:field_name)
      end

      it "refuses a body wrapped in a root key, naming the expected structure" do
        put api_v1_profile_document_parameters_path(profile), params: {
          baseline_parameters: { parameters: [ { param_id: "ac-1_prm_1", value: "ISSO" } ] }
        }, headers: auth_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        parsed = JSON.parse(response.body)
        expect(parsed["details"].join(" ")).to include("TOP LEVEL")
        expect(parsed["expected"]).to eq(
          "parameters" => [ { "param_id" => "string", "value" => "string" } ],
          "selections" => [ { "select_id" => "string", "selected" => [ "string" ] } ]
        )
        expect(field_names).to be_empty
      end

      it "refuses `parameters` sent as an object map instead of an array" do
        put api_v1_profile_document_parameters_path(profile), params: {
          parameters: { "ac-1_prm_1" => "ISSO" }
        }, headers: auth_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["details"].join(" ")).to include("must be an ARRAY")
        expect(field_names).to be_empty
      end

      it "refuses a body that did not arrive as JSON" do
        # No `as: :json`, so the body is form-encoded and `parameters` never
        # becomes an array of objects. This returned 200/0/0.
        put api_v1_profile_document_parameters_path(profile),
          params: { note: "no parameters here" }, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(field_names).to be_empty
      end

      it "refuses a `selected` that is a string rather than an array" do
        put api_v1_profile_document_parameters_path(profile), params: {
          selections: [ { select_id: "ac-2_prm_1", selected: "removes" } ]
        }, headers: auth_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["details"].join(" ")).to include("must be an ARRAY")
        expect(field_names).to be_empty
      end

      it "refuses a parameters entry carrying no param_id" do
        put api_v1_profile_document_parameters_path(profile), params: {
          parameters: [ { value: "ISSO" } ]
        }, headers: auth_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["details"].join(" ")).to include("missing `param_id`")
        expect(field_names).to be_empty
      end

      # The other direction: "nothing to do" is a legitimate request and must
      # stay distinguishable from "I did not understand you". A caller who
      # explicitly sends empty lists gets the 200 the old code gave everyone.
      it "accepts explicitly empty lists as a no-op" do
        put api_v1_profile_document_parameters_path(profile), params: {
          parameters: [], selections: []
        }, headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        parsed = JSON.parse(response.body)
        expect(parsed["data"]["parameters_updated"]).to eq(0)
        expect(parsed["data"]["selections_updated"]).to eq(0)
        expect(parsed["data"]["validation_errors"]).to be_empty
      end

      it "records no audit event for a refused payload" do
        expect {
          put api_v1_profile_document_parameters_path(profile), params: {
            baseline_parameters: { parameters: [ { param_id: "ac-1_prm_1", value: "ISSO" } ] }
          }, headers: auth_headers, as: :json
        }.not_to change(AuditEvent, :count)
      end
    end

    # ── #994: `selection_id` is the guess everybody makes ───────────────────
    describe "the selection_id alias (#994)" do
      before { create(:profile_control, profile_document: profile, control_id: "ac-2") }

      it "applies a selection sent as selection_id" do
        put api_v1_profile_document_parameters_path(profile), params: {
          selections: [ { selection_id: "ac-2_prm_1", selected: [ "removes" ] } ]
        }, headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["data"]["selections_updated"]).to eq(1)
        field = ProfileControlField.joins(:profile_control)
                                   .find_by(profile_controls: { profile_document_id: profile.id },
                                            field_name: "parameter:ac-2_prm_1")
        expect(field.field_value).to eq("removes")
      end

      it "names the id it could not find rather than reporting null" do
        put api_v1_profile_document_parameters_path(profile), params: {
          selections: [ { selection_id: "zz-9_odp.01", selected: [ "removes" ] } ]
        }, headers: auth_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        errors = JSON.parse(response.body)["data"]["validation_errors"]
        expect(errors.first["select_id"]).to eq("zz-9_odp.01")
        expect(errors.first["error"]).to eq("Unknown selection ID")
      end
    end

    it "returns 422 for unknown param_ids" do
      put api_v1_profile_document_parameters_path(profile), params: {
        parameters: [
          { param_id: "nonexistent", value: "test" }
        ]
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["validation_errors"]).not_to be_empty
    end
  end

  describe "GET /api/v1/profile_documents/:id/parameters/export" do
    it "exports as JSON by default" do
      get export_api_v1_profile_document_parameters_path(profile),
        headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
      parsed = JSON.parse(response.body)
      expect(parsed["baseline"]).to eq(profile.name)
    end

    it "exports as YAML" do
      get export_api_v1_profile_document_parameters_path(profile),
        params: { format: "yaml" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/yaml")
    end

    it "exports as XML" do
      get export_api_v1_profile_document_parameters_path(profile),
        params: { format: "xml" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/xml")
    end
  end

  describe "non-admin access" do
    let(:regular_user) { create(:user) }
    let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
    let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

    it "allows read access" do
      get api_v1_profile_document_parameters_path(profile), headers: user_headers
      expect(response).to have_http_status(:ok)
    end

    # #919 — BEHAVIOUR CHANGE. This example previously asserted "allows write
    # access (all authenticated)", which encoded a missing guard as intended
    # behaviour: any valid API token could rewrite a profile's baseline
    # parameters, the ODP tailoring an ATO package rests on.
    #
    # It was inconsistent as well as insecure — PUT /profile_documents/:id has
    # required profiles.write since #575, while PUT /profile_documents/:id/
    # parameters, which edits part of the same profile, required nothing.
    #
    # Found by spec/security/controller_authorization_coverage_spec.rb, not by
    # the original 16-controller survey, which looked only at the web surface.
    it "refuses a write without profiles.write" do
      create(:profile_control, profile_document: profile, control_id: "ac-1")

      put api_v1_profile_document_parameters_path(profile), params: {
        parameters: [ { param_id: "ac-1_prm_1", value: "test" } ]
      }, headers: user_headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    # The positive control: the guard must not lock out a legitimate editor.
    it "allows a write when the caller holds profiles.write" do
      grant_permission(regular_user, "profiles.write")
      create(:profile_control, profile_document: profile, control_id: "ac-1")

      put api_v1_profile_document_parameters_path(profile), params: {
        parameters: [ { param_id: "ac-1_prm_1", value: "test" } ]
      }, headers: user_headers, as: :json

      expect(response).to have_http_status(:ok)
    end
  end
end
