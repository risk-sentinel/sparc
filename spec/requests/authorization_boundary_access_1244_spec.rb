# frozen_string_literal: true

require "rails_helper"

# #1244 — every web action on an authorization boundary checks the caller's
# permission on THAT boundary.
#
# Before this, AuthorizationBoundariesController guarded only `bulk_destroy`.
# Any signed-in user who knew a slug could view, edit, update or delete a
# boundary, and build or download its ATO package. The controller-coverage
# sweep passed it, because one guarded action marked the whole controller
# guarded; that spec now checks per action.
#
# The rule, shared with Api::V1::AuthorizationBoundariesController:
#   read  (show, ATO wizard, ATO download)     authorization_boundaries.read on the boundary
#   write (edit, update, attach, ATO build)    authorization_boundaries.write on the boundary
#   create                                     authorization_boundaries.write, instance-level
#   destroy                                    instance administrator, as the API
#
# Also pinned: the ATO wizard's "select existing" took any document by id and
# moved it into this boundary. It now accepts only this boundary's documents
# (or boundary-less ones, for an administrator), as attach_document does.
#
# NIST 800-53: AC-3, AC-6.
RSpec.describe "Authorization boundary access (#1244)", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:own)     { create(:authorization_boundary, name: "Own System") }
  let(:foreign) { create(:authorization_boundary, name: "Foreign System") }
  let(:user)    { create(:user) }

  def refused?
    response.redirect? && !response.location.to_s.include?("/authorization_boundaries/")
  end

  describe "a caller with no permission on the boundary" do
    before do
      grant_permission(user, "authorization_boundaries.read", authorization_boundary: own)
      grant_permission(user, "authorization_boundaries.write", authorization_boundary: own)
      sign_in_as(user)
    end

    {
      "show"                 => ->(b) { [ :get,    "/authorization_boundaries/#{b.slug}" ] },
      "edit"                 => ->(b) { [ :get,    "/authorization_boundaries/#{b.slug}/edit" ] },
      "ato_wizard"           => ->(b) { [ :get,    "/authorization_boundaries/#{b.slug}/ato_wizard" ] },
      "download_ato_package" => ->(b) { [ :get,    "/authorization_boundaries/#{b.slug}/download_ato_package" ] },
      "attach_document"      => ->(b) { [ :get,    "/authorization_boundaries/#{b.slug}/attach_document?type=ssp" ] }
    }.each do |action, request|
      it "is refused #{action} on another boundary" do
        verb, path = request.call(foreign)
        public_send(verb, path)
        expect(refused?).to be(true), "#{action} on a foreign boundary answered #{response.status} #{response.location}"
      end
    end

    it "is refused update on another boundary, and nothing changes" do
      patch "/authorization_boundaries/#{foreign.slug}", params: { authorization_boundary: { name: "Taken over" } }
      expect(refused?).to be(true)
      expect(foreign.reload.name).to eq("Foreign System")
    end

    it "is refused destroy on another boundary, and it survives" do
      delete "/authorization_boundaries/#{foreign.slug}"
      expect(refused?).to be(true)
      expect(AuthorizationBoundary.exists?(foreign.id)).to be(true)
    end

    it "is refused building another boundary's ATO package" do
      post "/authorization_boundaries/#{foreign.slug}/create_ato_package", params: { ssp_mode: "skip" }
      expect(refused?).to be(true)
    end

    it "is refused destroy on its OWN boundary without being an administrator" do
      delete "/authorization_boundaries/#{own.slug}"
      expect(refused?).to be(true)
      expect(AuthorizationBoundary.exists?(own.id)).to be(true)
    end

    it "is refused creating a boundary without an instance-level write grant" do
      expect {
        post "/authorization_boundaries", params: { authorization_boundary: { name: "New System" } }
      }.not_to change(AuthorizationBoundary, :count)
      expect(refused?).to be(true)
    end
  end

  describe "a caller with the matching permission" do
    before { sign_in_as(user) }

    it "reads its boundary with authorization_boundaries.read" do
      grant_permission(user, "authorization_boundaries.read", authorization_boundary: own)
      get "/authorization_boundaries/#{own.slug}"
      expect(response).to have_http_status(:ok)
    end

    it "reads every boundary with an instance-level read grant" do
      grant_permission(user, "authorization_boundaries.read")
      get "/authorization_boundaries/#{foreign.slug}"
      expect(response).to have_http_status(:ok)
    end

    it "cannot edit with read alone" do
      grant_permission(user, "authorization_boundaries.read", authorization_boundary: own)
      get "/authorization_boundaries/#{own.slug}/edit"
      expect(refused?).to be(true)
    end

    it "updates its boundary with a boundary-scoped write grant" do
      grant_permission(user, "authorization_boundaries.write", authorization_boundary: own)
      patch "/authorization_boundaries/#{own.slug}", params: { authorization_boundary: { name: "Own System v2" } }
      expect(own.reload.name).to eq("Own System v2")
    end

    it "creates a boundary with an instance-level write grant" do
      grant_permission(user, "authorization_boundaries.write")
      expect {
        post "/authorization_boundaries", params: { authorization_boundary: { name: "New System" } }
      }.to change(AuthorizationBoundary, :count).by(1)
    end

    it "lets an administrator destroy a boundary" do
      admin = create(:user, :admin)
      sign_in_as(admin)
      delete "/authorization_boundaries/#{foreign.slug}"
      expect(AuthorizationBoundary.exists?(foreign.id)).to be(false)
    end
  end

  describe "the ATO wizard's existing documents" do
    let!(:own_ssp)     { create(:ssp_document, name: "Own SSP", authorization_boundary: own, status: "completed") }
    let!(:foreign_ssp) { create(:ssp_document, name: "Foreign SSP", authorization_boundary: foreign, status: "completed") }

    before do
      grant_permission(user, "authorization_boundaries.read", authorization_boundary: own)
      grant_permission(user, "authorization_boundaries.write", authorization_boundary: own)
      sign_in_as(user)
    end

    it "offers only this boundary's documents" do
      get "/authorization_boundaries/#{own.slug}/ato_wizard"
      expect(response.body).to include("Own SSP")
      expect(response.body).not_to include("Foreign SSP")
    end

    it "refuses to move another boundary's SSP into this one" do
      post "/authorization_boundaries/#{own.slug}/create_ato_package",
           params: { ssp_mode: "select_existing", ssp_document_id: foreign_ssp.id }
      expect(foreign_ssp.reload.authorization_boundary_id).to eq(foreign.id)
    end

    it "still links one of this boundary's own SSPs" do
      post "/authorization_boundaries/#{own.slug}/create_ato_package",
           params: { ssp_mode: "select_existing", ssp_document_id: own_ssp.id }
      expect(flash[:success]).to include("ATO package built")
      expect(own_ssp.reload.authorization_boundary_id).to eq(own.id)
    end
  end

  describe "through the API (one rule with the web)" do
    def headers_for(owner)
      { "Authorization" => "Bearer #{ApiToken.generate!(user: owner, name: "t").plaintext_token}" }
    end

    it "lets a boundary-scoped writer update its own boundary" do
      grant_permission(user, "authorization_boundaries.write", authorization_boundary: own)
      patch "/api/v1/authorization_boundaries/#{own.slug}",
            params: { authorization_boundary: { name: "Own via API" } }, headers: headers_for(user), as: :json
      expect(response).to have_http_status(:ok)
      expect(own.reload.name).to eq("Own via API")
    end

    it "refuses that writer on another boundary" do
      grant_permission(user, "authorization_boundaries.write", authorization_boundary: own)
      patch "/api/v1/authorization_boundaries/#{foreign.slug}",
            params: { authorization_boundary: { name: "Taken" } }, headers: headers_for(user), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(foreign.reload.name).to eq("Foreign System")
    end

    it "refuses create to a boundary-scoped writer, and allows an instance-level one" do
      grant_permission(user, "authorization_boundaries.write", authorization_boundary: own)
      post "/api/v1/authorization_boundaries",
           params: { authorization_boundary: { name: "API New" } }, headers: headers_for(user), as: :json
      expect(response).to have_http_status(:forbidden)

      grant_permission(user, "authorization_boundaries.write")
      post "/api/v1/authorization_boundaries",
           params: { authorization_boundary: { name: "API New" } }, headers: headers_for(user), as: :json
      expect(response).to have_http_status(:created)
    end
  end
end
