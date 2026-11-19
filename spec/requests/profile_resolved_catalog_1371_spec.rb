# frozen_string_literal: true

require "rails_helper"

# #1371 — a parameter saved on a draft baseline was missing from
# Export > JSON (Resolved). The download served the stored
# `resolved_catalog_json`, which is written at publish and at import, and
# "Create Editable Copy" duplicates it; an imported resolved profile was never
# re-resolved at all, not even at publish.
RSpec.describe "Resolved Catalog export (#1371)", type: :request do
  let(:user) { create(:user, :admin) }
  let(:param_id) { "ac-01_odp.05" }

  before do
    sign_in_as(user)
    allow(SparcConfig).to receive(:require_document_approval?).and_return(false)
  end

  let(:party_uuid) { SecureRandom.uuid }
  let(:valid_metadata) do
    {
      "roles" => [ { "id" => "prepared-by", "title" => "Prepared By" } ],
      "parties" => [ { "uuid" => party_uuid, "type" => "organization", "name" => "Test Org" } ],
      "responsible-parties" => [ { "role-id" => "prepared-by", "party-uuids" => [ party_uuid ] } ]
    }
  end

  let(:catalog) { create(:control_catalog) }
  let(:family) { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:ac1) do
    create(:catalog_control, control_family: family, control_id: "ac-1",
                             params_data: [ { "id" => param_id, "label" => "frequency" } ])
  end

  # A file in the shape an imported resolved profile stores, carrying "365".
  let(:imported_json) do
    { "catalog" => {
      "uuid" => SecureRandom.uuid,
      "metadata" => { "title" => "Imported baseline", "version" => "1.0", "oscal-version" => "1.1.2" },
      "groups" => [ { "id" => "ac", "title" => "Access Control", "controls" => [
        { "id" => "ac-1", "title" => "Policy and Procedures",
          "params" => [ { "id" => param_id, "label" => "frequency", "values" => [ "365" ] } ] }
      ] } ]
    } }
  end

  def draft(**attrs)
    defaults = { lifecycle_status: "in_progress", metadata_extra: valid_metadata, control_catalog: catalog }
    create(:profile_document, **defaults, **attrs).tap do |p|
      p.profile_controls.create!(control_id: "ac-1", title: "AC-1")
    end
  end

  def save_parameter(profile, value)
    control = profile.profile_controls.find_by!(control_id: "ac-1")
    patch parameters_profile_document_profile_control_path(profile, control),
          params: { param_values: { param_id => value } }
  end

  # The values JSON (Resolved) states for the parameter.
  def resolved_values(json)
    control, = ResolvedCatalog.wrap(json).each_control.find { |c, _| c["id"] == "ac-1" }
    Array(control&.dig("params")).find { |p| p["id"] == param_id }&.dig("values")
  end

  def download_resolved(profile)
    get download_resolved_catalog_profile_document_path(profile)
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  describe "a draft made with Create Editable Copy" do
    it "states the value saved on the copy, without publishing it" do
      published = draft
      save_parameter(published, "365")
      patch publish_profile_document_path(published)
      expect(published.reload).to be_published_lifecycle
      expect(resolved_values(published.resolved_catalog_json)).to eq([ "365" ])

      post copy_profile_document_path(published)
      copy = ProfileDocument.where.not(id: published.id).order(:id).last
      expect(copy).to be_draft
      save_parameter(copy, "at least annually")

      expect(resolved_values(download_resolved(copy))).to eq([ "at least annually" ])
    end
  end

  describe "a draft linked to a catalog that was never published" do
    it "is offered and states the saved value" do
      profile = draft
      save_parameter(profile, "at least annually")

      get profile_document_path(profile)
      expect(response.body).to include("JSON (Resolved)")
      expect(resolved_values(download_resolved(profile))).to eq([ "at least annually" ])
    end
  end

  describe "a published baseline" do
    it "serves the file stored at its publish" do
      profile = draft
      save_parameter(profile, "365")
      patch publish_profile_document_path(profile)
      expect(profile.reload).to be_published_lifecycle

      # Change the stored value behind the published document's back: the
      # download must still be the file stored at publish.
      ProfileControlField.joins(:profile_control)
                         .where(profile_controls: { profile_document_id: profile.id },
                                field_name: "parameter:#{param_id}")
                         .update_all(field_value: "changed later")

      expect(resolved_values(download_resolved(profile))).to eq([ "365" ])
    end
  end

  describe "an imported resolved profile" do
    let(:imported) do
      draft(import_metadata: { "format" => "oscal_resolved_profile" }, resolved_catalog_json: imported_json)
    end

    it "is resolved again at publish, so a saved value reaches the stored file" do
      save_parameter(imported, "at least annually")
      patch publish_profile_document_path(imported)

      expect(imported.reload).to be_published_lifecycle
      expect(resolved_values(imported.resolved_catalog_json)).to eq([ "at least annually" ])
    end

    it "states the saved value while it is a draft" do
      save_parameter(imported, "at least annually")
      expect(resolved_values(download_resolved(imported))).to eq([ "at least annually" ])
    end

    it "is not published without a linked catalog" do
      imported.update!(control_catalog: nil)
      patch publish_profile_document_path(imported)

      expect(imported.reload).not_to be_published_lifecycle
      expect(flash[:error]).to include("no source catalog linked")
    end

    it "serves its imported file while it is a draft with no catalog" do
      imported.update!(control_catalog: nil)
      expect(resolved_values(download_resolved(imported))).to eq([ "365" ])
    end
  end

  describe "a draft with no catalog and no stored file" do
    it "offers no download and says why" do
      profile = draft(control_catalog: nil)

      get profile_document_path(profile)
      expect(response.body).not_to include("JSON (Resolved)")

      get download_resolved_catalog_profile_document_path(profile)
      expect(response).to redirect_to(profile_document_path(profile))
      expect(flash[:error]).to include("Publish the profile first")
    end
  end
end
