# frozen_string_literal: true

require "rails_helper"

# #1249 — POST/PATCH /api/v1/back_matter_resources accepted any
# `resourceable_type` / `resourceable_id`, so a resource could be pointed at any
# model class, or at a record that does not exist. The owner must now be one of
# BackMatterResource::RESOURCEABLE_TYPES and must exist. Asserted both ways: the
# types the preserved data holds (nil, CdefDocument, ControlCatalog,
# ProfileDocument, SspDocument) stay valid, and the boundary is accepted.
RSpec.describe "Api::V1::BackMatterResources owner allow-list (#1249)", type: :request do
  let(:admin)   { create(:user, :admin) }
  let(:headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'bm-1249').plaintext_token}" } }
  let(:boundary) { create(:authorization_boundary) }
  let(:ssp)      { create(:ssp_document, authorization_boundary: boundary) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  def create_with(type, id)
    post api_v1_back_matter_resources_path, headers: headers, as: :json,
         params: { back_matter_resource: { title: "Owner check", resourceable_type: type, resourceable_id: id } }
  end

  describe "create" do
    it "refuses a type that cannot own back-matter, with 422, and saves nothing" do
      expect { create_with("User", admin.id) }.not_to change(BackMatterResource, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join).to include("not a type that can own back-matter")
    end

    it "refuses an owner that does not exist" do
      expect { create_with("SspDocument", 0) }.not_to change(BackMatterResource, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join).to include("does not exist")
    end

    it "refuses a type with no id" do
      create_with("SspDocument", nil)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "accepts an existing owner of an allowed type" do
      create_with("SspDocument", ssp.id)

      expect(response).to have_http_status(:created)
      expect(BackMatterResource.last.resourceable).to eq(ssp)
    end

    it "accepts an authorization boundary as owner" do
      create_with("AuthorizationBoundary", boundary.id)

      expect(response).to have_http_status(:created)
      expect(BackMatterResource.last.resourceable).to eq(boundary)
    end

    it "accepts no owner at all (a library resource)" do
      post api_v1_back_matter_resources_path, headers: headers, as: :json,
           params: { back_matter_resource: { title: "Library entry" } }

      expect(response).to have_http_status(:created)
      expect(BackMatterResource.last.resourceable_type).to be_nil
    end
  end

  describe "update" do
    let!(:resource) do
      BackMatterResource.create!(resourceable: ssp, title: "Owned", uuid: SecureRandom.uuid, source: "managed")
    end

    it "refuses moving a resource to a type that cannot own back-matter" do
      patch api_v1_back_matter_resource_path(resource), headers: headers, as: :json,
            params: { back_matter_resource: { resourceable_type: "ApiToken" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(resource.reload.resourceable).to eq(ssp)
    end

    it "refuses moving a resource to an owner that does not exist" do
      patch api_v1_back_matter_resource_path(resource), headers: headers, as: :json,
            params: { back_matter_resource: { resourceable_type: "CdefDocument", resourceable_id: 0 } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(resource.reload.resourceable).to eq(ssp)
    end

    it "moves a resource to an existing owner of an allowed type" do
      cdef = create(:cdef_document)
      patch api_v1_back_matter_resource_path(resource), headers: headers, as: :json,
            params: { back_matter_resource: { resourceable_type: "CdefDocument", resourceable_id: cdef.id } }

      expect(response).to have_http_status(:ok)
      expect(resource.reload.resourceable).to eq(cdef)
    end

    it "still edits a resource whose owner is unchanged" do
      patch api_v1_back_matter_resource_path(resource), headers: headers, as: :json,
            params: { back_matter_resource: { title: "Renamed" } }

      expect(response).to have_http_status(:ok)
      expect(resource.reload.title).to eq("Renamed")
    end
  end

  describe "the types the preserved data holds" do
    it "keeps each of them valid" do
      owners = [ nil, create(:cdef_document), create(:control_catalog), create(:profile_document), ssp ]

      owners.each do |owner|
        resource = BackMatterResource.new(resourceable: owner, title: "Kept", uuid: SecureRandom.uuid, source: "managed")
        expect(resource).to be_valid, "#{owner&.class || 'nil'} owner: #{resource.errors.full_messages.join(', ')}"
      end
    end
  end
end
