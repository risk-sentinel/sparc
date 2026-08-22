# frozen_string_literal: true

require "rails_helper"

# #1023 — an invalid enum value must be a 422 in JSON, not a 500 and an HTML
# error page.
#
# `Evidence` is the only model in the API using Rails enums, and enum assignment
# raises ArgumentError immediately — before validation runs, so nothing produces
# a validation error to render. Every other constrained field uses
# `validates :inclusion` and already answered 422; those are asserted here too,
# so the difference between the two mechanisms is pinned rather than assumed.
RSpec.describe "Api::V1 invalid enum values", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'T').plaintext_token}" }
  end
  let(:boundary) { create(:authorization_boundary) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  # Artifact evidence requires a file and at least one control link — the
  # enum-value checks below need a body that is otherwise VALID, so the 422 they
  # assert can only be about the enum.
  def valid_evidence_attributes(**overrides)
    {
      title: "Contract evidence",
      description: "Created by the spec",
      evidence_type: "artifact",
      status: "draft",
      source: "https://example.com/evidence",
      control_ids: "ac-2",
      authorization_boundary_id: boundary.id,
      file: Rack::Test::UploadedFile.new(
        StringIO.new("SPARC enum spec fixture"), "text/plain", original_filename: "e.txt"
      )
    }.merge(overrides)
  end

  describe "POST /api/v1/evidences" do
    %i[evidence_type status].each do |field|
      it "refuses an invalid #{field} with a JSON 422, not a 500" do
        post api_v1_evidences_path,
          params: { evidence: valid_evidence_attributes(field => "not-a-real-value") },
          headers: headers

        expect(response).to have_http_status(:unprocessable_content),
          "expected 422, got #{response.status}. A 500 here renders Rails' HTML " \
          "error page from a JSON API."
        expect(response.media_type).to eq("application/json")
        expect(response.parsed_body["details"].join).to include(field.to_s)
        expect(response.parsed_body["details"].join).to include("not-a-real-value")
      end
    end

    it "still creates evidence when the values are valid" do
      post api_v1_evidences_path, params: { evidence: valid_evidence_attributes },
        headers: headers

      expect(response).to have_http_status(:created), response.body
    end
  end

  describe "PATCH /api/v1/evidences/:id" do
    %i[evidence_type status].each do |field|
      it "refuses an invalid #{field} with a JSON 422, and changes nothing" do
        evidence = create(:evidence, authorization_boundary: boundary)
        before = evidence.attributes.slice("evidence_type", "status")

        patch api_v1_evidence_path(evidence),
          params: { evidence: { field => "not-a-real-value" } },
          headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.media_type).to eq("application/json")
        expect(evidence.reload.attributes.slice("evidence_type", "status")).to eq(before)
      end
    end
  end

  # The other constrained fields never had this problem, because they are
  # validated rather than enum-assigned. Asserted so the two mechanisms cannot
  # quietly converge on the broken one.
  describe "fields constrained by validates :inclusion" do
    it "refuses an invalid control_catalog lifecycle_status with 422" do
      post api_v1_control_catalogs_path,
        params: { control_catalog: { name: "C", version: "1", source: "s",
                                     lifecycle_status: "not-a-real-value" } },
        headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")
    end

    it "refuses an invalid role scope with 422" do
      post api_v1_roles_path,
        params: { role: { name: "r-#{SecureRandom.hex(4)}", display_name: "R",
                          scope: "not-a-real-value" } },
        headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")
    end
  end
end
