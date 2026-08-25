# frozen_string_literal: true

require "rails_helper"

# #945 — the mapping SHELL had a full API; its entries had none at all, so the
# web form was the only way to add or remove a control-to-control relationship.
RSpec.describe "Api::V1::ControlMappingEntries", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth)  { { "Authorization" => "Bearer #{token.plaintext_token}" } }

  let(:source_catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 5") }
  let(:target_catalog) { create(:control_catalog, name: "ISO 27001") }
  let(:mapping) do
    create(:control_mapping, source_catalog: source_catalog, target_catalog: target_catalog)
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)

    create(:control_family, control_catalog: source_catalog, code: "AC")
      .catalog_controls.create!(control_id: "ac-1", label: "AC-1", title: "Policy")
    create(:control_family, control_catalog: target_catalog, code: "A5")
      .catalog_controls.create!(control_id: "a.5.1", label: "A.5.1", title: "Policies")
  end

  def entries_path = "/api/v1/control_mappings/#{mapping.id}/entries"
  def entry_path(entry) = "#{entries_path}/#{entry.id}"

  def valid_attrs(**overrides)
    { source_control_id: "ac-1", target_control_id: "a.5.1",
      source_type: "control", target_type: "control",
      relationship: "equivalent" }.merge(overrides)
  end

  describe "POST create" do
    it "creates an entry naming controls that exist in both catalogs" do
      post entries_path, params: { control_mapping_entry: valid_attrs }, headers: auth

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)["data"]
      expect(body["source_control_id"]).to eq("ac-1")
      expect(body["resolved"]).to be true
    end

    # The model owns the rule, so the API is guarded by the same one as the
    # form rather than by a copy of it.
    it "refuses a control absent from the source catalog" do
      post entries_path,
           params: { control_mapping_entry: valid_attrs(source_control_id: "zz-99") },
           headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to have_key("source_control_id")
    end

    it "refuses a control taken from the wrong side of the mapping" do
      post entries_path,
           params: { control_mapping_entry: valid_attrs(source_control_id: "a.5.1") },
           headers: auth

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "does not create the entry when it refuses" do
      expect {
        post entries_path,
             params: { control_mapping_entry: valid_attrs(target_control_id: "nope") },
             headers: auth
      }.not_to change(ControlMappingEntry, :count)
    end
  end

  describe "PATCH update" do
    it "corrects an entry in place" do
      entry = create(:control_mapping_entry, control_mapping: mapping,
                     source_control_id: "ac-1", target_control_id: "a.5.1")

      patch entry_path(entry),
            params: { control_mapping_entry: { remarks: "clarified" } },
            headers: auth

      expect(response).to have_http_status(:ok)
      expect(entry.reload.remarks).to eq("clarified")
    end

    it "refuses to repoint an entry at a control that does not exist" do
      entry = create(:control_mapping_entry, control_mapping: mapping,
                     source_control_id: "ac-1", target_control_id: "a.5.1")

      patch entry_path(entry),
            params: { control_mapping_entry: { target_control_id: "not-a-control" } },
            headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(entry.reload.target_control_id).to eq("a.5.1")
    end
  end

  describe "DELETE destroy" do
    it "removes the entry" do
      entry = create(:control_mapping_entry, control_mapping: mapping,
                     source_control_id: "ac-1", target_control_id: "a.5.1")

      expect { delete entry_path(entry), headers: auth }
        .to change(ControlMappingEntry, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET index" do
    it "lists the mapping's entries and counts the unresolvable ones" do
      create(:control_mapping_entry, control_mapping: mapping,
             source_control_id: "ac-1", target_control_id: "a.5.1")
      # Written before the catalogs held it; stored, reported, never rewritten.
      stale = build(:control_mapping_entry, control_mapping: mapping,
                    source_control_id: "gone-1", target_control_id: "a.5.1")
      stale.save!(validate: false)

      get entries_path, headers: auth

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].length).to eq(2)
      expect(body["meta"]["unresolved"]).to eq(1)
      expect(body["data"].find { |e| e["source_control_id"] == "gone-1" }["unresolved_sides"])
        .to eq([ "source" ])
    end

    it "does not leak entries from another mapping" do
      other = create(:control_mapping, source_catalog: source_catalog, target_catalog: target_catalog)
      create(:control_mapping_entry, control_mapping: other,
             source_control_id: "ac-1", target_control_id: "a.5.1")

      get entries_path, headers: auth

      expect(JSON.parse(response.body)["data"]).to be_empty
    end
  end

  describe "authorization" do
    let(:plain) { create(:user) }
    let(:plain_token) { ApiToken.generate!(user: plain, name: "Plain") }
    let(:plain_auth) { { "Authorization" => "Bearer #{plain_token.plaintext_token}" } }

    it "refuses a write without mappings.write" do
      post entries_path, params: { control_mapping_entry: valid_attrs }, headers: plain_auth

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an unauthenticated write" do
      post entries_path, params: { control_mapping_entry: valid_attrs }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
