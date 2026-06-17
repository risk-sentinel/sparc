# frozen_string_literal: true

require "rails_helper"

# #646 — add an authoritative source. Any authenticated user can add one; it is
# org/boundary-scoped by default, and "instance-wide" is gated by the existing
# promotion approval (self-applied for promotion authority, else queued).
RSpec.describe "Authoritative source create (#646)", type: :request do
  before do
    allow_any_instance_of(ApplicationController).to receive(:require_authentication).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:check_session_timeout).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:check_password_reset).and_return(true)
  end

  let(:org) { create(:organization) }

  def org_member(organization)
    user = create(:user)
    create(:organization_membership, user: user, organization: organization, role: "org_admin")
    user
  end

  describe "GET /authoritative_sources/new" do
    it "renders the add form for any authenticated user" do
      sign_in_as(create(:user))
      get new_authoritative_source_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Add Authoritative Source")
    end
  end

  describe "POST /authoritative_sources" do
    it "creates an org/boundary-scoped source by default" do
      sign_in_as(org_member(org))

      expect {
        post authoritative_sources_path,
             params: { back_matter_resource: { title: "Org Policy", rel: "reference" } }
      }.to change(BackMatterResource, :count).by(1)

      r = BackMatterResource.order(:created_at).last
      expect(r.source).to eq("managed")
      expect(r.globally_available).to be(false)
      expect(r.organization_id).to eq(org.id)
      expect(r.resourceable).to be_nil
      expect(response).to redirect_to(authoritative_sources_path)
    end

    it "self-promotes to instance-wide for an admin when instance_wide is set" do
      sign_in_as(create(:user, :admin))

      post authoritative_sources_path,
           params: { back_matter_resource: { title: "Global Std", rel: "reference" },
                     instance_wide: "1" }

      r = BackMatterResource.order(:created_at).last
      expect(r.globally_available).to be(true)
      expect(r.source).to eq("authoritative")
      expect(r.promotion_status).to eq("approved")
    end

    it "queues for approval when a non-privileged user requests instance-wide" do
      sign_in_as(org_member(org))

      post authoritative_sources_path,
           params: { back_matter_resource: { title: "Wants global", rel: "reference" },
                     instance_wide: "1" }

      r = BackMatterResource.order(:created_at).last
      expect(r.globally_available).to be(false)        # not granted directly
      expect(r.promotion_status).to eq("pending_review") # waiting for an approver
    end

    it "re-renders with 422 on a validation error (missing title)" do
      sign_in_as(create(:user))
      post authoritative_sources_path, params: { back_matter_resource: { title: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "index visibility" do
    it "hides another org's scoped source from a non-admin" do
      other = create(:organization)
      BackMatterResource.create!(uuid: SecureRandom.uuid, title: "Other Org Secret",
                                 source: "managed", organization: other)
      user = org_member(org)
      allow(user).to receive(:has_permission?).and_return(true) # can view the library
      sign_in_as(user)

      get authoritative_sources_path
      expect(response.body).not_to include("Other Org Secret")
    end

    it "shows globally-available sources to everyone" do
      BackMatterResource.create!(uuid: SecureRandom.uuid, title: "Shared Global",
                                 source: "authoritative", globally_available: true,
                                 promotion_status: "approved")
      user = org_member(org)
      allow(user).to receive(:has_permission?).and_return(true)
      sign_in_as(user)

      get authoritative_sources_path
      expect(response.body).to include("Shared Global")
    end
  end
end
