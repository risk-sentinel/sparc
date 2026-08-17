# frozen_string_literal: true

require "rails_helper"

# #929 defect 3, API side.
#
# `Api::V1::DocumentBaseController#authorize_document_write!` computed
# `@document&.authorization_boundary_id || params[…]`, so once a document had a
# boundary the one being REQUESTED was never authorized. A caller holding
# `*.write` on boundary A could `PUT` a document into boundary B while holding
# nothing at all on B — and since the API is the surface an integrator drives
# unattended, that is the more dangerous half of the defect.
#
# Kept symmetrical with spec/requests/boundary_attachment_929_spec.rb, which
# pins the same rule for the web controllers.
RSpec.describe "Api::V1 boundary re-association (#929)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:source) { create(:authorization_boundary, name: "Source ATO") }
  let(:target) { create(:authorization_boundary, name: "Target ATO") }

  def token_headers(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'Test').plaintext_token}" }
  end

  # Each type: factory, permission key, and the member path builder.
  def type_matrix
    {
      "ssp"  => { factory: :ssp_document,  key: "ssp.write",  param: :ssp_document,
                  path: ->(d) { "/api/v1/ssp_documents/#{d.slug}" } },
      "sap"  => { factory: :sap_document,  key: "sap.write",  param: :sap_document,
                  path: ->(d) { "/api/v1/sap_documents/#{d.slug}" } },
      "sar"  => { factory: :sar_document,  key: "sar.write",  param: :sar_document,
                  path: ->(d) { "/api/v1/sar_documents/#{d.slug}" } },
      "poam" => { factory: :poam_document, key: "poam.write", param: :poam_document,
                  path: ->(d) { "/api/v1/poam_documents/#{d.slug}" } }
    }
  end

  it "refuses to move a document into a boundary the caller cannot write to, for every type" do
    type_matrix.each do |label, spec|
      user = create(:user)
      grant_permission(user, spec[:key], authorization_boundary: source)
      document = create(spec[:factory], authorization_boundary: source)

      put spec[:path].call(document),
          params: { spec[:param] => { authorization_boundary_id: target.id } },
          headers: token_headers(user)

      expect(document.reload.authorization_boundary_id).to eq(source.id),
        "#{label}: expected the move to be refused and the boundary unchanged"
      expect(response).to have_http_status(:forbidden), "#{label}: expected 403"
    end
  end

  it "allows the move when the caller holds write on BOTH boundaries" do
    user = create(:user)
    grant_permission(user, "ssp.write", authorization_boundary: source)
    grant_permission(user, "ssp.write", authorization_boundary: target)
    document = create(:ssp_document, authorization_boundary: source)

    put "/api/v1/ssp_documents/#{document.slug}",
        params: { ssp_document: { authorization_boundary_id: target.id } },
        headers: token_headers(user)

    expect(response).to have_http_status(:ok)
    expect(document.reload.authorization_boundary_id).to eq(target.id)
  end

  it "still allows an ordinary edit that does not touch the boundary" do
    user = create(:user)
    grant_permission(user, "ssp.write", authorization_boundary: source)
    document = create(:ssp_document, authorization_boundary: source)

    put "/api/v1/ssp_documents/#{document.slug}",
        params: { ssp_document: { description: "Reworded" } },
        headers: token_headers(user)

    expect(response).to have_http_status(:ok)
    expect(document.reload.description).to eq("Reworded")
    expect(document.authorization_boundary_id).to eq(source.id)
  end

  it "refuses attaching an orphan to a boundary the caller cannot write to" do
    user = create(:user)
    grant_permission(user, "ssp.write", authorization_boundary: source)
    document = create(:ssp_document, authorization_boundary: nil)

    put "/api/v1/ssp_documents/#{document.slug}",
        params: { ssp_document: { authorization_boundary_id: target.id } },
        headers: token_headers(user)

    expect(response).to have_http_status(:forbidden)
    expect(document.reload.authorization_boundary_id).to be_nil
  end

  it "lets an Instance-Admin move a document, as it always could" do
    admin = create(:user, :admin)
    document = create(:ssp_document, authorization_boundary: source)

    put "/api/v1/ssp_documents/#{document.slug}",
        params: { ssp_document: { authorization_boundary_id: target.id } },
        headers: token_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(document.reload.authorization_boundary_id).to eq(target.id)
  end
end
