# frozen_string_literal: true

require "rails_helper"

# #1249 — a boundary's OWN back-matter (diagrams, inventory, PPSM, CRM).
#
# The Completeness row "Back-matter documents" counted resources owned by the
# boundary, and no screen could create one, so the row stayed "Not started"
# for every UI user. The boundary page now has a Back Matter section, with an
# Api::V1 equivalent, both checked against THIS boundary:
#
#   read   authorization_boundaries.read AND back_matter.read
#   write  back_matter.write
#
# Editable in any boundary status (owner). The SSP's OSCAL back-matter carries
# these resources (owner: the SSP export carries boundary-level back-matter).
RSpec.describe "Boundary back-matter (#1249)", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:boundary) { create(:authorization_boundary, name: "BM System", status: "active") }
  let(:other)    { create(:authorization_boundary, name: "Other System") }
  let(:user)     { create(:user) }

  def grant(key, on: boundary) = grant_permission(user, key, authorization_boundary: on)

  def grant_reader(on: boundary)
    AuthorizationBoundary::BACK_MATTER_READ_PERMISSIONS.each { |key| grant(key, on: on) }
  end

  let(:form) { { back_matter_resource: { title: "Network diagram", rel: "diagram", href: "https://example.gov/d.pdf" } } }

  describe "the boundary page section" do
    def page = Nokogiri::HTML(response.body)

    it "is shown, with Add/Edit/Delete, to a reader who may write, in a non-draft boundary" do
      grant_reader
      grant("back_matter.write")
      boundary.back_matter_resources.create!(title: "Inventory", uuid: SecureRandom.uuid, source: "managed")
      sign_in_as(user)

      get authorization_boundary_path(boundary)

      section = page.at_css("#boundary-back-matter")
      expect(section).to be_present
      expect(section.text).to include("Inventory")
      expect(section.at_css("form[action='#{authorization_boundary_back_matter_resources_path(boundary)}']")).to be_present
      expect(section.text).to include("Edit")
    end

    it "is read-only to a reader without back_matter.write" do
      grant_reader
      boundary.back_matter_resources.create!(title: "Inventory", uuid: SecureRandom.uuid, source: "managed")
      sign_in_as(user)

      get authorization_boundary_path(boundary)

      section = page.at_css("#boundary-back-matter")
      expect(section.text).to include("Inventory")
      expect(section.at_css("form[action='#{authorization_boundary_back_matter_resources_path(boundary)}']")).to be_nil
      expect(section.css("button").map(&:text).join).not_to include("Edit")
    end

    it "is absent for someone who may read the boundary but not its back-matter" do
      grant(AuthorizationBoundary::READ_PERMISSION)
      sign_in_as(user)

      get authorization_boundary_path(boundary)

      expect(response).to have_http_status(:ok)
      expect(page.at_css("#boundary-back-matter")).to be_nil
    end
  end

  describe "web create / update / destroy" do
    it "creates on an active (non-draft) boundary for back_matter.write on that boundary" do
      grant("back_matter.write")
      sign_in_as(user)

      expect { post authorization_boundary_back_matter_resources_path(boundary), params: form }
        .to change { boundary.back_matter_resources.count }.by(1)
      expect(response).to redirect_to(authorization_boundary_path(boundary, anchor: "boundary-back-matter"))
      expect(boundary.back_matter_resources.last).to have_attributes(source: "managed", rel: "diagram")
    end

    it "refuses back_matter.write held on ANOTHER boundary" do
      grant("back_matter.write", on: other)
      sign_in_as(user)

      expect { post authorization_boundary_back_matter_resources_path(boundary), params: form }
        .not_to change(BackMatterResource, :count)
      expect(response).to redirect_to(root_path)
    end

    it "refuses a reader without write" do
      grant_reader
      sign_in_as(user)

      expect { post authorization_boundary_back_matter_resources_path(boundary), params: form }
        .not_to change(BackMatterResource, :count)
    end

    it "updates and deletes the boundary's resource" do
      grant("back_matter.write")
      sign_in_as(user)
      resource = boundary.back_matter_resources.create!(title: "Old", uuid: SecureRandom.uuid, source: "managed")

      patch authorization_boundary_back_matter_resource_path(boundary, resource),
            params: { back_matter_resource: { title: "PPSM" } }
      expect(resource.reload.title).to eq("PPSM")

      expect { delete authorization_boundary_back_matter_resource_path(boundary, resource) }
        .to change { boundary.back_matter_resources.count }.by(-1)
    end

    it "cannot reach another boundary's resource through this boundary" do
      grant("back_matter.write")
      sign_in_as(user)
      foreign = other.back_matter_resources.create!(title: "Foreign", uuid: SecureRandom.uuid, source: "managed")

      delete authorization_boundary_back_matter_resource_path(boundary, foreign)

      expect(response).to have_http_status(:not_found)
      expect(BackMatterResource.exists?(foreign.id)).to be(true)
    end
  end

  describe "the Completeness row" do
    it "turns Complete once the boundary has back-matter" do
      row = -> { BoundaryReadinessService.new(boundary.reload).report[:sections].find { |s| s[:key] == :back_matter } }
      expect(row.call[:status]).to eq(:absent)

      boundary.back_matter_resources.create!(title: "CRM", uuid: SecureRandom.uuid, source: "managed")

      expect(row.call[:status]).to eq(:complete)
    end
  end

  describe "Api::V1 .../authorization_boundaries/:id/back_matter_resources" do
    let(:headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'bbm').plaintext_token}" } }
    let(:index_path) { "/api/v1/authorization_boundaries/#{boundary.id}/back_matter_resources" }

    it "lists for a caller holding both read keys on the boundary" do
      grant_reader
      boundary.back_matter_resources.create!(title: "Inventory", uuid: SecureRandom.uuid, source: "managed")

      get index_path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].map { |r| r["title"] }).to eq([ "Inventory" ])
    end

    it "refuses a list to a caller holding only one of the two read keys" do
      grant(AuthorizationBoundary::READ_PERMISSION)

      get index_path, headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a list when the read keys are held on another boundary" do
      grant_reader(on: other)

      get index_path, headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "creates, updates and deletes for back_matter.write on the boundary (by slug too)" do
      grant("back_matter.write")

      post "/api/v1/authorization_boundaries/#{boundary.slug}/back_matter_resources",
           headers: headers, params: form, as: :json
      expect(response).to have_http_status(:created)
      id = response.parsed_body.dig("data", "id")
      expect(BackMatterResource.find(id).resourceable).to eq(boundary)

      patch "#{index_path}/#{id}", headers: headers, as: :json,
            params: { back_matter_resource: { title: "Renamed diagram" } }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "title")).to eq("Renamed diagram")

      delete "#{index_path}/#{id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(BackMatterResource.exists?(id)).to be(false)
    end

    it "refuses a write without back_matter.write on the boundary" do
      grant_reader
      grant("back_matter.write", on: other)

      post index_path, headers: headers, params: form, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(boundary.back_matter_resources.count).to eq(0)
    end

    it "never takes the owner from the body" do
      grant("back_matter.write")

      post index_path, headers: headers, as: :json,
           params: { back_matter_resource: { title: "X", resourceable_type: "SspDocument", resourceable_id: 1 } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(BackMatterResource.count).to eq(0)
    end

    it "answers 404 for another boundary's resource" do
      grant("back_matter.write")
      foreign = other.back_matter_resources.create!(title: "Foreign", uuid: SecureRandom.uuid, source: "managed")

      delete "#{index_path}/#{foreign.id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(BackMatterResource.exists?(foreign.id)).to be(true)
    end
  end

  describe "the SSP's OSCAL back-matter" do
    before { ensure_control("AC-2", title: "Account Management") }

    let(:ssp) do
      create(:ssp_document, authorization_boundary: boundary).tap do |doc|
        create(:ssp_control, ssp_document: doc, control_id: "AC-2", title: "Account Management")
      end
    end
    let!(:diagram) do
      boundary.back_matter_resources.create!(title: "Boundary diagram", uuid: SecureRandom.uuid,
                                             source: "managed", href: "https://example.gov/diagram.pdf",
                                             media_type: "application/pdf")
    end

    def back_matter_uuids(json)
      JSON.parse(json).dig("system-security-plan", "back-matter", "resources").map { |r| r["uuid"] }
    end

    it "carries the boundary's own back-matter, and the export is schema-valid" do
      json = OscalSspExportService.new(ssp).export

      expect(back_matter_uuids(json)).to include(diagram.uuid)
      result = OscalSchemaValidationService.validate(:ssp, JSON.parse(json), version: "1.2.3")
      expect(result.errors).to be_empty
    end

    it "does not carry another boundary's back-matter" do
      foreign = other.back_matter_resources.create!(title: "Foreign", uuid: SecureRandom.uuid, source: "managed")

      expect(back_matter_uuids(OscalSspExportService.new(ssp).export)).not_to include(foreign.uuid)
    end
  end
end
