# frozen_string_literal: true

require "rails_helper"

# #1270 — PUT /api/v1/profile_documents/:id/controls/bulk makes the change the
# Profile screen's bulk bar and inline priority selector make.
RSpec.describe "Api::V1 profile controls bulk edit (#1270)", type: :request do
  let(:profile) { create(:profile_document) }
  let!(:ac1) { create(:profile_control, profile_document: profile, control_id: "ac-1", priority: nil) }
  let!(:ac2) { create(:profile_control, profile_document: profile, control_id: "ac-2", priority: "P3") }
  let!(:resource) { create(:back_matter_resource, globally_available: true) }
  let(:path) { "/api/v1/profile_documents/#{profile.slug}/controls/bulk" }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'caller').plaintext_token}" }
  end

  let(:author) { create(:user).tap { grant_permission(_1, "profiles.write") } }
  let(:curator) do
    create(:user).tap do |u|
      grant_permission(u, "profiles.write")
      grant_permission(u, "back_matter.write")
    end
  end

  it "sets priority and links a resource in one change, and audits it" do
    put path, headers: headers_for(curator), as: :json,
              params: { control_ids: %w[ac-1 AC-2], priority: "P1", link_resource_ids: [ resource.id ] }

    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body["data"]).to include("control_ids" => %w[ac-1 ac-2], "priority" => "P1",
                                                    "priority_changed" => true, "linked" => 2, "unlinked" => 0)
    expect([ ac1.reload.priority, ac2.reload.priority ]).to eq(%w[P1 P1])
    expect(ac2.back_matter_resources).to eq([ resource ])
    expect(AuditEvent.where(action: "profile_controls_bulk_edited").count).to eq(1)

    get "/api/v1/profile_documents/#{profile.slug}", headers: headers_for(curator)
    expect(response.parsed_body.dig("data", "control_priorities")).to eq("ac-1" => "P1", "ac-2" => "P1")
  end

  it "clears priority on null, and leaves it alone when the key is absent" do
    put path, headers: headers_for(author), as: :json, params: { control_ids: %w[ac-2], priority: nil }
    expect(response).to have_http_status(:ok), response.body
    expect(ac2.reload.priority).to be_nil

    ac2.update!(priority: "P2")
    put path, headers: headers_for(curator), as: :json, params: { control_ids: %w[ac-2], unlink_resource_ids: [ resource.id ] }
    expect(response).to have_http_status(:ok), response.body
    expect(ac2.reload.priority).to eq("P2")
  end

  it "refuses an unknown control with 422 and changes nothing" do
    put path, headers: headers_for(author), as: :json, params: { control_ids: %w[ac-1 zz-9], priority: "P1" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("Not in this profile: zz-9")
    expect(ac1.reload.priority).to be_nil
  end

  it "refuses a published profile with 422" do
    profile.update!(lifecycle_status: "published")

    put path, headers: headers_for(author), as: :json, params: { control_ids: %w[ac-1], priority: "P1" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(ac1.reload.priority).to be_nil
  end

  describe "permissions, both directions" do
    it "refuses a caller without profiles.write" do
      put path, headers: headers_for(create(:user)), as: :json, params: { control_ids: %w[ac-1], priority: "P1" }

      expect(response).to have_http_status(:forbidden)
      expect(ac1.reload.priority).to be_nil
    end

    it "refuses linking without back_matter.write" do
      put path, headers: headers_for(author), as: :json,
                params: { control_ids: %w[ac-1], priority: "P1", link_resource_ids: [ resource.id ] }

      expect(response).to have_http_status(:forbidden)
      expect(ac1.reload.priority).to be_nil
      expect(ac1.back_matter_resources).to be_empty
    end
  end
end
