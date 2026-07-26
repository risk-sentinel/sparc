# frozen_string_literal: true

require "rails_helper"

# #757 — profile baseline control selection API (PUT .../controls).
RSpec.describe "Api::V1 profile controls", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:cc1)    { create(:catalog_control, control_family: family, control_id: "ac-1") }
  let!(:cc2)    { create(:catalog_control, control_family: family, control_id: "ac-2") }
  let(:profile) { create(:profile_document, control_catalog: catalog) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def path(p = profile) = controls_api_v1_profile_document_path(p.slug)

  it "selects controls from the linked catalog" do
    put path, params: { control_ids: [ "ac-1", "ac-2" ] }, headers: admin_headers
    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)["data"]
    expect(data["added"]).to eq(2)
    expect(data["controls_count"]).to eq(2)
    expect(profile.profile_controls.pluck(:control_id)).to contain_exactly("ac-1", "ac-2")
  end

  it "diffs on a subsequent call" do
    put path, params: { control_ids: [ "ac-1" ] }, headers: admin_headers
    put path, params: { control_ids: [ "ac-2" ] }, headers: admin_headers
    data = JSON.parse(response.body)["data"]
    expect(data["added"]).to eq(1)
    expect(data["removed"]).to eq(1)
  end

  it "422 when the profile has no linked catalog" do
    orphan = create(:profile_document, control_catalog: nil)
    put path(orphan), params: { control_ids: [ "ac-1" ] }, headers: admin_headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to match(/no source catalog/)
  end

  it "401 without a token" do
    put path, params: { control_ids: [ "ac-1" ] }
    expect(response).to have_http_status(:unauthorized)
  end

  it "403 for a member without profiles.write" do
    put path, params: { control_ids: [ "ac-1" ] }, headers: member_headers
    expect(response).to have_http_status(:forbidden)
  end
end
