# frozen_string_literal: true

require "rails_helper"

# #630 — UI review/approval workflow wiring. Authority + separation-of-duties
# logic is unit-tested in spec/services/document_approval_service_spec.rb; these
# specs confirm the controller actions transition state, gate publish behind the
# flag, and block submitting an empty document.
RSpec.describe "Document approval workflow", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:admin) { create(:user, :admin) }

  # Valid OSCAL publication metadata (so publish reaches the approval gate).
  let(:valid_metadata) do
    party_uuid = SecureRandom.uuid
    creator_role = "prepared-by"
    {
      "roles" => [ { "id" => creator_role, "title" => "Prepared By" } ],
      "parties" => [ { "uuid" => party_uuid, "type" => "organization", "name" => "Org" } ],
      "responsible-parties" => [ { "role-id" => creator_role, "party-uuids" => [ party_uuid ] } ]
    }
  end

  describe "Control Catalog submit → approve → reject" do
    let(:catalog) { create(:control_catalog) }

    it "submits a draft catalog for review" do
      sign_in_as(admin)
      post submit_for_review_control_catalog_path(catalog)
      expect(catalog.reload.approval_status).to eq("pending_review")
    end

    it "approves a pending catalog" do
      catalog.submit_for_review!(create(:user))
      sign_in_as(admin)
      post approve_control_catalog_path(catalog)
      expect(catalog.reload.approval_status).to eq("approved")
    end

    it "rejects a pending catalog with a reason" do
      catalog.submit_for_review!(create(:user))
      sign_in_as(admin)
      post reject_control_catalog_path(catalog), params: { reason: "needs work" }
      expect(catalog.reload.approval_status).to eq("rejected")
      expect(catalog.rejection_reason).to eq("needs work")
    end
  end

  describe "publish gate when SPARC_REQUIRE_DOCUMENT_APPROVAL is enabled" do
    let(:catalog) { create(:control_catalog, lifecycle_status: "in_progress", metadata_extra: valid_metadata) }

    before do
      allow(SparcConfig).to receive(:require_document_approval?).and_return(true)
      sign_in_as(admin)
    end

    it "blocks publishing a non-approved document" do
      patch publish_control_catalog_path(catalog)
      expect(catalog.reload.published_lifecycle?).to be(false)
      expect(flash[:error]).to match(/reviewed and approved/i)
    end

    it "allows publishing once approved" do
      catalog.update!(approval_status: "approved")
      patch publish_control_catalog_path(catalog)
      expect(catalog.reload.published_lifecycle?).to be(true)
    end
  end

  describe "publish is unaffected when the flag is off (default)" do
    it "publishes a non-approved catalog (gate disabled)" do
      catalog = create(:control_catalog, lifecycle_status: "in_progress", metadata_extra: valid_metadata)
      sign_in_as(admin)
      patch publish_control_catalog_path(catalog)
      expect(catalog.reload.published_lifecycle?).to be(true)
    end
  end

  describe "empty CDEF cannot be submitted for review (#634)" do
    it "blocks submit and keeps it in draft" do
      cdef = create(:cdef_document) # no controls
      sign_in_as(admin)
      post submit_for_review_cdef_document_path(cdef)
      expect(cdef.reload.approval_status).to eq("draft")
      expect(flash[:error]).to match(/required content/i)
    end
  end

  describe "review queue" do
    it "lists documents pending review that the user can approve" do
      catalog = create(:control_catalog)
      catalog.submit_for_review!(create(:user))
      sign_in_as(admin)

      get review_queue_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(catalog.name)
    end
  end
end
