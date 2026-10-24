# frozen_string_literal: true

require "rails_helper"

# #1275 — a boundary-scoped `cdef.approve` grant approves its boundary's
# component definitions, and nothing wider. The approver is a SHIPPED ISSO
# (BuiltInRoleSeeder) held on boundary X, so these fail if the shipped role
# loses the key as well as if the rule breaks. Both directions, web and API.
RSpec.describe "Boundary-scoped cdef.approve (#1275)", type: :request do
  let(:organization) { create(:organization) }
  let(:x) { create(:authorization_boundary) }
  let(:y) { create(:authorization_boundary) }

  def boundary_user(role, boundary)
    create(:user).tap do |user|
      create(:user_role, user: user, role: Role.find_by!(name: role), authorization_boundary_id: boundary.id)
      create(:organization_membership, user: user, organization: organization)
    end
  end

  let(:isso) { boundary_user("isso", x) }
  let(:submitter) { boundary_user("so_iso", x) }
  let(:policy_manager) do
    create(:user).tap do |user|
      create(:user_role, user: user, role: Role.find_by!(name: "policy_manager"))
      create(:organization_membership, user: user, organization: organization)
    end
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    BuiltInRoleSeeder.call
  end

  def pending(cdef, by: submitter)
    cdef.update_columns(approval_status: "pending_review", submitted_by_user_id: by.id, submitted_at: Time.current)
    cdef
  end

  def scoped_to(boundary)
    create(:cdef_document, cdef_type: "custom").tap do |cdef|
      CdefScopeService.apply(cdef, scope: "boundary", authorization_boundary_id: boundary.id)
    end
  end

  let!(:on_x) { pending(scoped_to(x)) }
  let!(:on_y) { pending(scoped_to(y)) }
  let!(:org_wide) { pending(create(:cdef_document, cdef_type: "custom", globally_available: true, organization: organization)) }
  let!(:unassigned) { pending(create(:cdef_document, cdef_type: "custom")) }

  def headers(user) = { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }

  def refusals = AuditEvent.where(action: "cdef_document_approval_refused")

  describe "the rule" do
    it "approves its boundary's CDEF, and nothing scoped elsewhere or wider" do
      expect(CdefWriteAccess.may_approve?(isso, on_x)).to be(true)
      [ on_y, org_wide, unassigned ].each { expect(CdefWriteAccess.may_approve?(isso, _1)).to be(false), _1.name }

      approvals = [ on_x, on_y, org_wide, unassigned ].map { DocumentApprovalService.new(document: _1, actor: policy_manager).can_approve? }
      expect(approvals).to all(be(true))
    end

    it "is not given approval by linking a CDEF to an environment" do
      BoundaryCdefDocument.create!(boundary: create(:boundary, authorization_boundary: x), cdef_document: on_y)
      expect(CdefWriteAccess.may_approve?(isso, on_y)).to be(false)
    end

    it "still refuses the boundary approver who submitted it" do
      pending(on_x, by: isso)
      expect(DocumentApprovalService.new(document: on_x, actor: isso).can_approve?).to be(false)
    end

    it "leaves catalogs and profiles to instance-level approvers" do
      catalog = create(:control_catalog)
      catalog.update_columns(approval_status: "pending_review", submitted_by_user_id: submitter.id)
      expect(DocumentApprovalService.new(document: catalog, actor: isso).can_approve?).to be(false)
    end
  end

  describe "web" do
    before { sign_in_as(isso) }

    it "approves its boundary's CDEF" do
      post approve_cdef_document_path(on_x)

      expect(on_x.reload.approval_status).to eq("approved")
      expect(on_x.approved_by_user_id).to eq(isso.id)
      expect(AuditEvent.where(action: "cdef_document_approved").for_subject(on_x)).to exist
    end

    it "rejects its boundary's CDEF with a reason" do
      post reject_cdef_document_path(on_x), params: { reason: "Invented: statements incomplete" }
      expect(on_x.reload.approval_status).to eq("rejected")
    end

    it "is refused another boundary's, an organization-wide and an unassigned CDEF, and each refusal is recorded" do
      [ on_y, org_wide, unassigned ].each do |cdef|
        expect { post approve_cdef_document_path(cdef) }.to change(refusals, :count).by(1)
        expect(cdef.reload.approval_status).to eq("pending_review"), cdef.name
        expect(flash[:error]).to eq("Not authorized to approve this document")
      end

      expect { post reject_cdef_document_path(on_y), params: { reason: "Invented" } }.to change(refusals, :count).by(1)
      expect(refusals.order(:id).last.metadata).to include("attempted" => "reject")
      expect(refusals.order(:id).last.user).to eq(isso)
    end

    it "lists only its boundary's CDEFs in the review queue" do
      get review_queue_index_path
      names = Nokogiri::HTML(response.body).text

      expect(names).to include(on_x.name)
      [ on_y, org_wide, unassigned ].each { expect(names).not_to include(_1.name) }
    end
  end

  describe "API" do
    it "approves and rejects its boundary's CDEF, and is refused another's" do
      post "/api/v1/cdef_documents/#{on_x.slug}/approve", headers: headers(isso), as: :json
      expect(response).to have_http_status(:ok), response.body
      expect(on_x.reload.approval_status).to eq("approved")

      [ on_y, org_wide, unassigned ].each do |cdef|
        expect {
          post "/api/v1/cdef_documents/#{cdef.slug}/reject", headers: headers(isso), as: :json, params: { reason: "Invented" }
        }.to change(refusals, :count).by(1)
        expect(response).to have_http_status(:forbidden), cdef.name
        expect(cdef.reload.approval_status).to eq("pending_review")
      end
    end

    it "does not let a boundary approver publish without review; an instance approver may" do
      draft = scoped_to(x)
      patch "/api/v1/cdef_documents/#{draft.slug}", headers: headers(submitter), as: :json,
            params: { cdef_document: { lifecycle_status: "published" } }
      expect(response).to have_http_status(:forbidden), response.body
      expect(response.parsed_body["details"].join).to include("cdef.approve across the instance")
      expect(draft.reload.published_lifecycle?).to be(false)

      expect(DocumentApprovalService.new(document: draft, actor: submitter).can_approve?).to be(true)
      expect(DocumentApprovalService.new(document: draft, actor: policy_manager).may_publish_without_review?).to be(true)
    end
  end
end
