# frozen_string_literal: true

require "rails_helper"

# #980 made "instance-wide" admin-only on the web: it publishes a CDEF to every
# organization on the instance, including ones the requester does not belong
# to. The API reaches the same change through PATCH .../scope, which checked
# only `cdef.write` — proven: a non-admin writer got 200 and published the CDEF
# instance-wide. Both directions below, plus the scopes that stay open.
RSpec.describe "Api::V1 CDEF scope: instance-wide is instance authority", type: :request do
  let(:cdef) { create(:cdef_document) }
  let(:writer) do
    role = create(:role, name: "cdef_writer_probe", scope: "instance", permissions: { "cdef.write" => true, "cdef.read" => true })
    create(:user).tap { |u| create(:user_role, user: u, role: role) }
  end
  let(:admin) { create(:user, :admin) }

  def headers_for(user) = { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 't').plaintext_token}" }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  it "refuses a non-admin holding cdef.write" do
    patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "instance" }, headers: headers_for(writer)

    expect(response).to have_http_status(:forbidden)
    expect(cdef.reload.globally_available).not_to be(true)
  end

  it "still lets a non-admin writer choose a non-instance scope" do
    patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "global" }, headers: headers_for(writer)

    expect(response).to have_http_status(:ok)
  end

  it "allows an instance administrator" do
    patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "instance" }, headers: headers_for(admin)

    expect(response).to have_http_status(:ok)
  end
end
