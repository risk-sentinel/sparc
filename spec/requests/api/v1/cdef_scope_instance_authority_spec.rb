# frozen_string_literal: true

require "rails_helper"

# #980 made "instance-wide" admin-only on the web: it publishes a CDEF to every
# organization on the instance, including ones the requester does not belong
# to. The API reaches the same change through PATCH .../scope, which checked
# only `cdef.write` — proven: a non-admin writer got 200 and published the CDEF
# instance-wide. #1257 then settled who may: whoever holds `cdef.write` across
# the instance (Policy Manager, or a role an administrator gives it at instance
# level), and an instance administrator. A grant scoped to one boundary is
# not that. Both directions below, plus the scopes that stay open.
RSpec.describe "Api::V1 CDEF scope: instance-wide is instance authority", type: :request do
  let(:cdef) { create(:cdef_document) }
  let(:writer) do
    role = create(:role, name: "cdef_writer_probe", scope: "instance", permissions: { "cdef.write" => true, "cdef.read" => true })
    create(:user).tap { |u| create(:user_role, user: u, role: role) }
  end
  let(:admin) { create(:user, :admin) }

  def headers_for(user) = { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 't').plaintext_token}" }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  it "allows a non-admin holding cdef.write across the instance" do
    patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "instance" }, headers: headers_for(writer)

    expect(response).to have_http_status(:ok)
    expect(cdef.reload.scope_tier).to eq(:instance)
  end

  it "refuses a writer whose cdef.write is scoped to one boundary" do
    boundary = create(:authorization_boundary)
    role = create(:role, name: "cdef_boundary_writer_probe", scope: "authorization_boundary",
                         permissions: { "cdef.write" => true, "cdef.read" => true })
    boundary_writer = create(:user).tap { |u| create(:user_role, user: u, role: role, authorization_boundary_id: boundary.id) }

    patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "instance" }, headers: headers_for(boundary_writer)

    expect(response).to have_http_status(:forbidden)
    expect(cdef.reload.scope_tier).not_to eq(:instance)
  end

  # No real caller who reaches this action lacks cdef.write across the
  # instance, so the check is made to refuse, proving the API consults it.
  it "refuses the tier, changing nothing, when the instance-wide check refuses" do
    allow(CdefScopeService).to receive(:may_scope_instance?).and_return(false)

    patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "instance" }, headers: headers_for(writer)

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["error"]).to eq(CdefScopeService::INSTANCE_SCOPE_REFUSAL)
    expect(cdef.reload.scope_tier).not_to eq(:instance)
  end

  it "still lets a non-admin writer choose a non-instance scope" do
    create(:organization_membership, user: writer)

    patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "global" }, headers: headers_for(writer)

    expect(response).to have_http_status(:ok)
    expect(cdef.reload.scope_tier).to eq(:organization)
  end

  # #1257 — "global" with no organization to own it was stored with a NULL
  # organization, which is the instance tier: this writer reached instance-wide
  # through the scope it IS allowed, past the refusal above.
  it "refuses organization-wide to a writer with no organization, instead of widening it" do
    patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "global" }, headers: headers_for(writer)

    expect(response).to have_http_status(:unprocessable_content)
    expect(cdef.reload.globally_available).not_to be(true)
    expect(cdef.scope_tier).not_to eq(:instance)
  end

  it "allows an instance administrator" do
    patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "instance" }, headers: headers_for(admin)

    expect(response).to have_http_status(:ok)
  end

  # #1257 — `scope` reads "global" for organization-wide and instance-wide
  # alike; `scope_tier` tells them apart, so the change can be read back.
  it "reports each tier on read as scope_tier" do
    org = create(:organization)
    create(:organization_membership, user: admin, organization: org)
    read = lambda do
      get "/api/v1/cdef_documents/#{cdef.slug}", headers: headers_for(admin)
      response.parsed_body["data"].values_at("scope", "scope_tier")
    end

    patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "instance" }, headers: headers_for(admin)
    expect(read.call).to eq(%w[global instance])

    patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "global" }, headers: headers_for(admin)
    expect(read.call).to eq(%w[global organization])
  end
end
