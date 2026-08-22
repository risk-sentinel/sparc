# frozen_string_literal: true

require "rails_helper"

# #1011 — converters and their entries through the API.
#
# The refresh endpoint is the interesting one: it is asynchronous, so what it
# must NOT do is report success for work that has not happened.
RSpec.describe "Api::V1::Converters", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:reader) { create(:user) }
  let(:writer) { create(:user) }

  let(:writer_role) { create(:role, name: "converter_writer_#{SecureRandom.hex(4)}") }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    writer_role.assign_permissions("converters.write" => true)
    writer_role.save!
    create(:user_role, user: writer, role: writer_role, authorization_boundary: nil)
  end

  let(:valid_attributes) do
    { name: "CCI Map #{SecureRandom.hex(4)}", converter_type: "cci_to_nist",
      status: "draft", source_framework: "DISA CCI", target_framework: "NIST SP 800-53" }
  end

  describe "POST /api/v1/converters" do
    it "creates the converter, confirmed by an independent read" do
      expect {
        post api_v1_converters_path, params: { converter: valid_attributes },
          headers: headers_for(writer), as: :json
      }.to change(Converter, :count).by(1)

      expect(response).to have_http_status(:created)
      id = response.parsed_body.dig("data", "id")

      get api_v1_converter_path(id), headers: headers_for(reader)
      expect(response.parsed_body.dig("data", "name")).to eq(valid_attributes[:name])
      expect(response.parsed_body.dig("data", "refreshable")).to be(true)
    end

    it "refuses an unknown converter_type" do
      post api_v1_converters_path,
        params: { converter: valid_attributes.merge(converter_type: "invented") },
        headers: headers_for(writer), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a caller without converters.write, and creates nothing" do
      expect {
        post api_v1_converters_path, params: { converter: valid_attributes },
          headers: headers_for(reader), as: :json
      }.not_to change(Converter, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an unauthenticated caller" do
      post api_v1_converters_path, params: { converter: valid_attributes }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # #919 removed converters.read — any authenticated user may read them, so the
  # absence of a check is deliberate and is pinned here so a later "fix" is a
  # failing test rather than a silent narrowing.
  describe "reads are open to any authenticated caller" do
    it "lets a user with no converter permission read the list and a record" do
      converter = create(:converter)

      get api_v1_converters_path, headers: headers_for(reader)
      expect(response).to have_http_status(:ok)

      get api_v1_converter_path(converter), headers: headers_for(reader)
      expect(response).to have_http_status(:ok)
    end

    it "still refuses an unauthenticated caller" do
      get api_v1_converters_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/converters/:id/refresh" do
    it "enqueues the job and answers 202, not 200 — the work has not happened yet" do
      converter = create(:converter, converter_type: "cci_to_nist", status: "draft")

      expect {
        post refresh_api_v1_converter_path(converter), headers: headers_for(writer), as: :json
      }.to have_enqueued_job(ConverterRefreshJob).with(converter.id)

      expect(response).to have_http_status(:accepted)
      expect(converter.reload.status).to eq("processing")
      expect(response.parsed_body.dig("data", "refresh", "enqueued")).to be(true)
    end

    it "refuses a converter type with no refresh service, naming the ones that have" do
      converter = create(:converter, converter_type: "custom")

      expect {
        post refresh_api_v1_converter_path(converter), headers: headers_for(writer), as: :json
      }.not_to have_enqueued_job(ConverterRefreshJob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["expected"]).to include("cci_to_nist")
    end

    it "refuses a second refresh while one is already running" do
      converter = create(:converter, converter_type: "cci_to_nist", status: "processing")

      expect {
        post refresh_api_v1_converter_path(converter), headers: headers_for(writer), as: :json
      }.not_to have_enqueued_job(ConverterRefreshJob)

      expect(response).to have_http_status(:conflict)
    end

    it "refuses a caller without converters.write, and enqueues nothing" do
      converter = create(:converter, converter_type: "cci_to_nist")

      expect {
        post refresh_api_v1_converter_path(converter), headers: headers_for(reader), as: :json
      }.not_to have_enqueued_job(ConverterRefreshJob)

      expect(response).to have_http_status(:forbidden)
      expect(converter.reload.status).not_to eq("processing")
    end
  end

  describe "GET /api/v1/converters/:id/export" do
    it "includes every entry" do
      converter = create(:converter)
      converter.converter_entries.create!(source_id: "CCI-000001", target_id: "AC-1",
                                          relationship: "equal")

      get export_api_v1_converter_path(converter), headers: headers_for(reader)

      expect(response).to have_http_status(:ok)
      entries = response.parsed_body.dig("data", "entries")
      expect(entries.map { |e| e["source_id"] }).to include("CCI-000001")
    end
  end

  describe "entries" do
    let(:converter) { create(:converter) }

    it "creates an entry and lists it" do
      post api_v1_converter_entries_path(converter),
        params: { converter_entry: { source_id: "CCI-000123", target_id: "AC-2",
                                     relationship: "equal" } },
        headers: headers_for(writer), as: :json

      expect(response).to have_http_status(:created)

      get api_v1_converter_entries_path(converter), headers: headers_for(reader)
      expect(response.parsed_body["data"].map { |e| e["source_id"] }).to include("CCI-000123")
    end

    it "filters by source_id truthfully" do
      converter.converter_entries.create!(source_id: "CCI-000001", target_id: "AC-1",
                                          relationship: "equal")
      converter.converter_entries.create!(source_id: "CCI-000002", target_id: "AU-2",
                                          relationship: "equal")

      get api_v1_converter_entries_path(converter), params: { source_id: "CCI-000001" },
        headers: headers_for(reader)

      sources = response.parsed_body["data"].map { |e| e["source_id"] }
      expect(sources).to eq([ "CCI-000001" ])
    end

    it "refuses a relationship outside the enumerated set" do
      post api_v1_converter_entries_path(converter),
        params: { converter_entry: { source_id: "CCI-000999", target_id: "AC-3",
                                     relationship: "vaguely_related" } },
        headers: headers_for(writer), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a duplicate source/target pair in the same converter" do
      converter.converter_entries.create!(source_id: "CCI-000777", target_id: "AC-7",
                                          relationship: "equal")

      post api_v1_converter_entries_path(converter),
        params: { converter_entry: { source_id: "CCI-000777", target_id: "AC-7",
                                     relationship: "equal" } },
        headers: headers_for(writer), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "deletes an entry, and it stops listing" do
      entry = converter.converter_entries.create!(source_id: "CCI-000555", target_id: "AC-5",
                                                  relationship: "equal")

      expect {
        delete api_v1_converter_entry_path(converter, entry), headers: headers_for(writer)
      }.to change { converter.converter_entries.count }.by(-1)

      expect(response).to have_http_status(:ok)

      get api_v1_converter_entries_path(converter), headers: headers_for(reader)
      expect(response.parsed_body["data"].map { |e| e["id"] }).not_to include(entry.id)
    end

    it "refuses a reader creating an entry, and creates nothing" do
      target = converter
      expect {
        post api_v1_converter_entries_path(target),
          params: { converter_entry: { source_id: "CCI-000404", target_id: "AC-4",
                                       relationship: "equal" } },
          headers: headers_for(reader), as: :json
      }.not_to change { target.converter_entries.count }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/converters/:id" do
    it "deletes the converter and reports how many entries went with it" do
      converter = create(:converter)
      converter.converter_entries.create!(source_id: "CCI-000010", target_id: "AC-1",
                                          relationship: "equal")

      delete api_v1_converter_path(converter), headers: headers_for(writer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "entries_deleted")).to eq(1)
      expect(Converter.exists?(converter.id)).to be(false)
    end

    it "refuses a reader, and the converter survives" do
      converter = create(:converter)

      delete api_v1_converter_path(converter), headers: headers_for(reader)

      expect(response).to have_http_status(:forbidden)
      expect(Converter.exists?(converter.id)).to be(true)
    end
  end
end
