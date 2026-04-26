# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Promotion Queue UI", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }
  let!(:pending_resource) do
    BackMatterResource.create!(uuid: SecureRandom.uuid, title: "Awaiting Review",
                               resourceable: ssp, source: "managed",
                               promotion_status: "pending_review")
  end

  before do
    sign_in_as(admin)
    allow_any_instance_of(ApplicationController).to receive(:require_authentication).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:check_session_timeout).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:check_password_reset).and_return(true)
  end

  describe "GET /promotion_queue" do
    it "shows pending resources the admin can approve" do
      get promotion_queue_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Awaiting Review")
    end

    it "shows nothing for a user with no approval authority" do
      bystander = create(:user)
      sign_in_as(bystander)

      get promotion_queue_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Awaiting Review")
      expect(response.body).to include("No pending promotions")
    end
  end

  describe "POST /promotion_queue/:id/approve" do
    it "promotes the resource and redirects with a success flash" do
      post approve_promotion_queue_path(pending_resource)
      expect(response).to redirect_to(promotion_queue_index_path)
      pending_resource.reload
      expect(pending_resource.source).to eq("authoritative")
      expect(pending_resource.globally_available).to eq(true)
    end
  end

  describe "POST /promotion_queue/:id/reject" do
    it "rejects with the supplied reason" do
      post reject_promotion_queue_path(pending_resource), params: { reason: "Not enough detail" }
      expect(response).to redirect_to(promotion_queue_index_path)
      pending_resource.reload
      expect(pending_resource.promotion_status).to eq("rejected")
      expect(pending_resource.rejection_reason).to eq("Not enough detail")
    end
  end
end
