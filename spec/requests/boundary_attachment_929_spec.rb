# frozen_string_literal: true

require "rails_helper"

# #929 — a document that did not associate to its boundary at upload could never
# be attached to one afterwards.
#
# Three defects, all covered here:
#   1. the boundary screen's "Add…" tile linked to the unfiltered document index
#   2. `document_metadata_params` omitted `authorization_boundary_id` on all four
#      types, while `Api::V1` permitted it — so the only recovery was calling the
#      API by hand
#   3. re-association was authorized against the CURRENT boundary, never the
#      TARGET, so write on A was enough to move a document into B
#
# The guards no-op unless auth is enabled, so every context stubs it. Without
# that stub these specs pass against a completely unguarded app.
RSpec.describe "Attaching a document to an authorization boundary (#929)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  # Each type: factory, permission key, and the attach path builder.
  def type_matrix
    {
      "ssp"  => { factory: :ssp_document,  key: "ssp.write",
                  path: ->(d) { "/ssp_documents/#{d.slug}/attach_boundary" } },
      "sap"  => { factory: :sap_document,  key: "sap.write",
                  path: ->(d) { "/sap_documents/#{d.slug}/attach_boundary" } },
      "sar"  => { factory: :sar_document,  key: "sar.write",
                  path: ->(d) { "/sar_documents/#{d.slug}/attach_boundary" } },
      "poam" => { factory: :poam_document, key: "poam.write",
                  path: ->(d) { "/poam_documents/#{d.slug}/attach_boundary" } }
    }
  end

  let(:target)  { create(:authorization_boundary, name: "Target ATO") }
  let(:other)   { create(:authorization_boundary, name: "Other ATO") }

  describe "attaching an orphan (the reported recovery case)" do
    it "attaches a boundary-less document for a user with write on the target, for every type" do
      type_matrix.each do |label, spec|
        user = create(:user)
        grant_permission(user, spec[:key], authorization_boundary: target)
        sign_in_as(user)

        document = create_legacy_orphan(spec[:factory])

        patch spec[:path].call(document),
              params: { authorization_boundary_id: target.id }

        expect(document.reload.authorization_boundary_id).to eq(target.id),
          "#{label}: expected the orphan to be attached to the target boundary"
      end
    end

    it "records the attachment as an audit event with both the old and new boundary" do
      user = create(:user)
      grant_permission(user, "ssp.write", authorization_boundary: target)
      sign_in_as(user)
      document = create_legacy_orphan(:ssp_document)

      expect {
        patch "/ssp_documents/#{document.slug}/attach_boundary",
              params: { authorization_boundary_id: target.id }
      }.to change { AuditEvent.where(action: "ssp_document_boundary_attached").count }.by(1)

      metadata = AuditEvent.where(action: "ssp_document_boundary_attached").last.metadata
      expect(metadata["authorization_boundary_id"]).to eq(target.id)
      expect(metadata["previous_authorization_boundary_id"]).to be_nil
    end

    it "attaches a PUBLISHED orphan — the document most in need of repair" do
      user = create(:user)
      grant_permission(user, "ssp.write", authorization_boundary: target)
      sign_in_as(user)
      document = create_legacy_orphan(:ssp_document, lifecycle_status: "published")

      patch "/ssp_documents/#{document.slug}/attach_boundary",
            params: { authorization_boundary_id: target.id }

      expect(document.reload.authorization_boundary_id).to eq(target.id)
    end

    it "returns to the boundary when the attach came from its Add… tile" do
      user = create(:user)
      grant_permission(user, "ssp.write", authorization_boundary: target)
      sign_in_as(user)
      document = create_legacy_orphan(:ssp_document)

      patch "/ssp_documents/#{document.slug}/attach_boundary",
            params: { authorization_boundary_id: target.id, return_to: "boundary" }

      expect(response).to redirect_to(authorization_boundary_path(target))
    end
  end

  describe "authorization against the TARGET boundary (defect 3)" do
    it "refuses to move a document into a boundary the caller cannot write to" do
      type_matrix.each do |label, spec|
        user = create(:user)
        # Write on the boundary the document is LEAVING, nothing on the target.
        grant_permission(user, spec[:key], authorization_boundary: other)
        sign_in_as(user)

        document = create(spec[:factory], authorization_boundary: other)

        patch spec[:path].call(document),
              params: { authorization_boundary_id: target.id }

        expect(document.reload.authorization_boundary_id).to eq(other.id),
          "#{label}: expected the move to be refused and the boundary unchanged"
        expect(response).to redirect_to(root_path)
      end
    end

    it "refuses an orphan attach when the caller holds nothing on the target" do
      user = create(:user)
      grant_permission(user, "ssp.write", authorization_boundary: other)
      sign_in_as(user)
      document = create_legacy_orphan(:ssp_document)

      patch "/ssp_documents/#{document.slug}/attach_boundary",
            params: { authorization_boundary_id: target.id }

      expect(document.reload.authorization_boundary_id).to be_nil
      expect(response).to redirect_to(root_path)
    end

    # `authorization_boundary_id` is ALSO the filter param name on every index
    # screen, so the top-level form of it is honoured for the attach action
    # only. Without that restriction a query string would choose which boundary
    # got authorized: appending it to any write on a boundary-less document
    # would swap an instance-level check for a check against a boundary the
    # caller happens to hold.
    it "does not let a top-level query param choose which boundary is authorized" do
      user = create(:user)
      grant_permission(user, "ssp.write", authorization_boundary: target)
      sign_in_as(user)
      orphan = create_legacy_orphan(:ssp_document)

      delete "/ssp_documents/#{orphan.slug}?authorization_boundary_id=#{target.id}"

      expect(SspDocument.find_by(id: orphan.id)).to be_present
      expect(response).to redirect_to(root_path)
    end

    it "allows the move when the caller holds write on BOTH boundaries" do
      user = create(:user)
      grant_permission(user, "ssp.write", authorization_boundary: other)
      grant_permission(user, "ssp.write", authorization_boundary: target)
      sign_in_as(user)
      document = create(:ssp_document, authorization_boundary: other)

      patch "/ssp_documents/#{document.slug}/attach_boundary",
            params: { authorization_boundary_id: target.id }

      expect(document.reload.authorization_boundary_id).to eq(target.id)
    end
  end

  describe "the lifecycle rule" do
    it "refuses to RE-POINT a published document that already has a boundary" do
      user = create(:user)
      grant_permission(user, "ssp.write", authorization_boundary: other)
      grant_permission(user, "ssp.write", authorization_boundary: target)
      sign_in_as(user)
      document = create(:ssp_document, authorization_boundary: other, lifecycle_status: "published")

      patch "/ssp_documents/#{document.slug}/attach_boundary",
            params: { authorization_boundary_id: target.id }

      expect(document.reload.authorization_boundary_id).to eq(other.id)
      expect(flash[:error]).to match(/published/i)
    end
  end

  describe "bad input" do
    let(:user) do
      u = create(:user)
      grant_permission(u, "ssp.write", authorization_boundary: target)
      u
    end

    before { sign_in_as(user) }

    it "reports a missing boundary id instead of silently doing nothing" do
      document = create_legacy_orphan(:ssp_document)

      patch "/ssp_documents/#{document.slug}/attach_boundary", params: {}

      expect(document.reload.authorization_boundary_id).to be_nil
      expect(flash[:error]).to be_present
    end

    # Authorization runs first and fails closed: nobody holds write on a
    # boundary that does not exist, so the request is refused before the
    # action's own existence check is reached. The `find_by` nil guard in
    # BoundaryAttachable stays as defence in depth for the no-auth instance.
    it "refuses a boundary id that does not exist, and writes nothing" do
      document = create_legacy_orphan(:ssp_document)
      missing_id = AuthorizationBoundary.maximum(:id).to_i + 1000

      patch "/ssp_documents/#{document.slug}/attach_boundary",
            params: { authorization_boundary_id: missing_id }

      expect(document.reload.authorization_boundary_id).to be_nil
      expect(response).to redirect_to(root_path)
    end

    it "reports a vanished boundary on an instance with no auth configured" do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(false)
      document = create_legacy_orphan(:ssp_document)
      missing_id = AuthorizationBoundary.maximum(:id).to_i + 1000

      patch "/ssp_documents/#{document.slug}/attach_boundary",
            params: { authorization_boundary_id: missing_id }

      expect(document.reload.authorization_boundary_id).to be_nil
      expect(flash[:error]).to match(/no longer exists/i)
    end
  end

  describe "the metadata form path (defect 2)" do
    it "writes the boundary through update_metadata, as Api::V1 always could" do
      user = create(:user)
      grant_permission(user, "ssp.write", authorization_boundary: target)
      sign_in_as(user)
      document = create_legacy_orphan(:ssp_document)

      patch "/ssp_documents/#{document.slug}/update_metadata",
            params: { ssp_document: { authorization_boundary_id: target.id } }

      expect(document.reload.authorization_boundary_id).to eq(target.id)
    end

    it "refuses through update_metadata when the caller lacks write on the target" do
      user = create(:user)
      grant_permission(user, "ssp.write", authorization_boundary: other)
      sign_in_as(user)
      document = create(:ssp_document, authorization_boundary: other)

      patch "/ssp_documents/#{document.slug}/update_metadata",
            params: { ssp_document: { authorization_boundary_id: target.id } }

      expect(document.reload.authorization_boundary_id).to eq(other.id)
    end
  end

  describe "the Add… tile (defect 1)" do
    let(:admin) { create(:user, :admin) }

    before { sign_in_as(admin) }

    it "leads to a screen that lists boundary-less documents of that type" do
      orphan   = create_legacy_orphan(:ssp_document, name: "Unattached Plan")
      attached = create(:ssp_document, authorization_boundary: other, name: "Already Attached Plan")

      get attach_document_authorization_boundary_path(target, type: "ssp")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(orphan.name)
      expect(response.body).not_to include(attached.name)
    end

    it "offers an upload link carrying the boundary through, for every type" do
      %w[ssp sap sar poam].each do |type|
        get attach_document_authorization_boundary_path(target, type: type)

        expect(response).to have_http_status(:ok), "#{type}: expected the attach screen to render"
        expect(response.body).to include("authorization_boundary_id=#{target.id}"),
          "#{type}: expected the upload link to pre-select the boundary"
      end
    end

    it "rejects an unknown document type rather than raising" do
      get attach_document_authorization_boundary_path(target, type: "wat")

      expect(response).to redirect_to(authorization_boundary_path(target))
    end

    it "shows a non-admin no orphans — they are Instance-Admin-only under #952" do
      sign_in_as(create(:user))
      orphan = create_legacy_orphan(:ssp_document, name: "Unattached Plan")

      get attach_document_authorization_boundary_path(target, type: "ssp")

      expect(response.body).not_to include(orphan.name)
    end
  end
end
