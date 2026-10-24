# frozen_string_literal: true

require "rails_helper"

# #1275 — a boundary-scoped `cdef.approve` grant approves its boundary's
# component definitions, and nothing wider. The approver is a SHIPPED ISSO
# (BuiltInRoleSeeder) held on boundary X, so these fail if the shipped role
# loses the key as well as if the rule breaks. Both directions, web and API.
RSpec.describe "Boundary-scoped cdef.approve (#1275)", type: :request do
  let(:organization) { create(:organization) }
  let(:x) { create(:authorization_boundary, organization: organization) }
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

  # The tree: Instance > Organization > Boundary. Nearly anyone authors on a
  # boundary; a wider scope is asked for at submit and approved at the tier it
  # reaches (owner, 2026-10-24).
  describe "a wider scope, approved at the tier it reaches" do
    let(:author) { submitter }
    let(:draft) { scoped_to(x).tap { create(:cdef_control, cdef_document: _1) } }

    def submit(cdef, scope, by: author) =
      DocumentApprovalService.new(document: cdef, actor: by).submit_for_review!(requested_scope: scope)

    def approve(cdef, by:) = DocumentApprovalService.new(document: cdef, actor: by).approve!

    it "makes it instance-wide once Policy Manager approves, and never on a boundary approver's say" do
      expect(submit(draft, "instance")).to be_success
      expect(draft.reload.requested_scope).to eq("instance")
      expect(draft.scope_tier).to eq(:boundary)

      expect(approve(draft, by: isso).status_code).to eq(:forbidden)
      expect(draft.reload.approval_status).to eq("pending_review")
      expect(draft.scope_tier).to eq(:boundary)

      expect(approve(draft, by: policy_manager)).to be_success
      draft.reload
      expect(draft.scope_tier).to eq(:instance)
      expect(draft.requested_scope).to be_nil
      expect(draft.approved_by_user_id).to eq(policy_manager.id)
      expect(AuditEvent.where(action: "cdef_document_approved").for_subject(draft).last.metadata).to include("scope" => "instance")
    end

    it "makes it organization-wide in its boundary's organization once that boundary's approver approves" do
      expect(submit(draft, "global")).to be_success
      expect(approve(draft, by: isso)).to be_success

      draft.reload
      expect(draft.scope_tier).to eq(:organization)
      expect(draft.organization_id).to eq(organization.id)
    end

    it "refuses an organization-wide request to approvers of other boundaries, in the same organization or another" do
      submit(draft, "global")
      sibling = create(:authorization_boundary, organization: organization)
      elsewhere = create(:authorization_boundary, organization: create(:organization))

      [ boundary_user("isso", sibling), boundary_user("isso", elsewhere), boundary_user("isso", y) ].each do |other|
        expect(approve(draft, by: other).status_code).to eq(:forbidden)
      end
      expect(draft.reload.scope_tier).to eq(:boundary)
    end

    it "keeps the submitter from approving at every tier; the instance administrator may" do
      %w[global instance].each do |scope|
        cdef = scoped_to(x).tap { create(:cdef_control, cdef_document: _1) }
        submit(cdef, scope, by: policy_manager)
        expect(approve(cdef, by: policy_manager).status_code).to eq(:forbidden), scope
      end

      cdef = scoped_to(x).tap { create(:cdef_control, cdef_document: _1) }
      admin = create(:user, :admin)
      submit(cdef, "instance", by: admin)
      expect(approve(cdef, by: admin)).to be_success
      expect(cdef.reload.scope_tier).to eq(:instance)
    end

    it "refuses a request it cannot grant, and leaves the CDEF a draft" do
      orphan_boundary = create(:authorization_boundary, organization: nil)
      orphan = scoped_to(orphan_boundary).tap { create(:cdef_control, cdef_document: _1) }
      expect(submit(orphan, "global").error).to include("belongs to none")

      instance_wide = create(:cdef_document, cdef_type: "custom", globally_available: true).tap { create(:cdef_control, cdef_document: _1) }
      expect(submit(instance_wide, "instance").error).to include("already available")
      expect(submit(draft, "everywhere").error).to include("organization-wide (global) or instance-wide (instance)")

      catalog = create(:control_catalog)
      expect(DocumentApprovalService.new(document: catalog, actor: author)
               .submit_for_review!(requested_scope: "instance").error).to include("Only a component definition")

      [ orphan, instance_wide, draft ].each { expect(_1.reload.approval_status).to eq("draft") }
      expect(draft.requested_scope).to be_nil
    end

    it "approves nothing when the scope can no longer be applied, and says why" do
      submit(draft, "global")
      x.update_columns(organization_id: nil)

      result = approve(draft, by: isso)
      expect(result.status_code).to eq(:conflict)
      expect(result.error).to include("needs an organization")
      expect(draft.reload.approval_status).to eq("pending_review")
      expect(draft.scope_tier).to eq(:boundary)
      expect(AuditEvent.where(action: "cdef_document_approved").for_subject(draft)).not_to exist
    end

    it "drops the request when it is rejected" do
      submit(draft, "instance")
      DocumentApprovalService.new(document: draft, actor: policy_manager).reject!(reason: "Invented: too broad")
      expect(draft.reload.requested_scope).to be_nil
      expect(draft.scope_tier).to eq(:boundary)
    end

    it "lists an instance-wide request for Policy Manager, saying what approving grants, and not for the boundary approver" do
      submit(draft, "instance")

      sign_in_as(isso)
      get review_queue_index_path
      expect(response.body).not_to include(draft.name)

      sign_in_as(policy_manager)
      get review_queue_index_path(view: "list")
      row = Nokogiri::HTML(response.body).css("tr").find { _1.text.include?(draft.name) }
      expect(row.at_css("[data-testid=review-scope-request]").text).to eq("Approving makes it available instance-wide")

      get review_queue_index_path(view: "card")
      expect(response.body).to include("Approving makes it available instance-wide")
    end

    it "is held to the two wider scopes by the database" do
      expect { draft.update_column(:requested_scope, "boundary") }.to raise_error(ActiveRecord::StatementInvalid, /requested_scope_values/)
    end
  end

  describe "the CDEF page" do
    let(:draft) { scoped_to(x).tap { create(:cdef_control, cdef_document: _1) } }

    def page_for(user, cdef)
      sign_in_as(user)
      get cdef_document_path(cdef)
      Nokogiri::HTML(response.body)
    end

    it "submits what the page renders, asking for instance-wide, and reads it back" do
      form = page_for(submitter, draft).at_css("form[data-testid=cdef-submit-for-review]")
      options = form.css("select[name=requested_scope] option").map { _1["value"] }
      expect(options).to eq([ "", "global", "instance" ])

      fields = form.css("input[type=hidden]").to_h { [ _1["name"], _1["value"] ] }
      post form["action"], params: fields.merge("requested_scope" => "instance")

      expect(draft.reload.approval_status).to eq("pending_review")
      expect(draft.requested_scope).to eq("instance")
      doc = page_for(submitter, draft)
      expect(doc.at_css("[data-testid=cdef-approval-status]").text).to eq("Pending Review")
      expect(doc.at_css("[data-testid=cdef-requested-scope]").text).to eq("instance-wide")
    end

    it "shows Approve to the boundary's approver for its own request, never to the submitter, and not for an instance-wide request" do
      DocumentApprovalService.new(document: draft, actor: submitter).submit_for_review!(requested_scope: "global")
      approver_page = page_for(isso, draft)
      expect(approver_page.at_css("[data-testid=cdef-approval] input[value=Reject]")).to be_present
      expect(approver_page.css("[data-testid=cdef-approval] button").map(&:text)).to eq([ "Approve" ])
      expect(page_for(submitter, draft).at_css("[data-testid=cdef-approval] input[value=Reject]")).to be_nil
      expect(page_for(isso, on_y).at_css("[data-testid=cdef-approval] input[value=Reject]")).to be_nil

      wide = scoped_to(x).tap { create(:cdef_control, cdef_document: _1) }
      DocumentApprovalService.new(document: wide, actor: submitter).submit_for_review!(requested_scope: "instance")
      expect(page_for(isso, wide).at_css("[data-testid=cdef-approval] input[value=Reject]")).to be_nil
      expect(page_for(policy_manager, wide).at_css("[data-testid=cdef-approval] input[value=Reject]")).to be_present
    end

    it "offers Submit to a writer of this boundary's draft only" do
      expect(page_for(submitter, draft).at_css("form[data-testid=cdef-submit-for-review]")).to be_present
      expect(page_for(isso, draft).at_css("form[data-testid=cdef-submit-for-review]")).to be_nil
      expect(page_for(boundary_user("so_iso", y), draft).at_css("form[data-testid=cdef-submit-for-review]")).to be_nil

      draft.update_columns(lifecycle_status: "published")
      expect(page_for(submitter, draft).at_css("form[data-testid=cdef-submit-for-review]")).to be_nil
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

    it "takes a wider scope at submit and reports it" do
      draft = scoped_to(x).tap { create(:cdef_control, cdef_document: _1) }
      post "/api/v1/cdef_documents/#{draft.slug}/submit_for_review", headers: headers(submitter), as: :json,
           params: { requested_scope: "instance" }
      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body["data"]).to include("requested_scope" => "instance", "scope_tier" => "boundary")

      post "/api/v1/cdef_documents/#{draft.slug}/approve", headers: headers(policy_manager), as: :json
      expect(response.parsed_body["data"]).to include("requested_scope" => nil, "scope_tier" => "instance")
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
