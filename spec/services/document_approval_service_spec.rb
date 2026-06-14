# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentApprovalService do
  let(:author)   { create(:user) }
  let(:approver) { create(:user, :admin) }

  # ControlCatalog has no content-completeness requirement, so it exercises the
  # bare state machine cleanly.
  let(:catalog) { create(:control_catalog) }

  describe "#submit_for_review!" do
    it "moves a draft document to pending_review and records the submitter" do
      result = described_class.new(document: catalog, actor: author).submit_for_review!

      expect(result).to be_success
      expect(catalog.reload.approval_status).to eq("pending_review")
      expect(catalog.submitted_by_user).to eq(author)
      expect(catalog.submitted_at).to be_present
    end

    it "rejects re-submitting a document already pending review" do
      catalog.submit_for_review!(author)
      result = described_class.new(document: catalog, actor: author).submit_for_review!

      expect(result).not_to be_success
      expect(result.status_code).to eq(:conflict)
    end

    it "blocks submitting a content-incomplete document (e.g. empty CDEF, #634)" do
      cdef = create(:cdef_document) # no controls → content-incomplete
      result = described_class.new(document: cdef, actor: author).submit_for_review!

      expect(result).not_to be_success
      expect(result.error).to match(/missing required content/i)
      expect(cdef.reload.approval_status).to eq("draft")
    end
  end

  describe "#approve!" do
    before { catalog.submit_for_review!(author) }

    it "approves a pending document (admin) and records the approver" do
      result = described_class.new(document: catalog, actor: approver).approve!

      expect(result).to be_success
      expect(catalog.reload.approval_status).to eq("approved")
      expect(catalog.approved_by_user).to eq(approver)
    end

    it "blocks self-approval by the submitter (separation of duties)" do
      author_with_perm = author
      allow(author_with_perm).to receive(:admin?).and_return(false)
      allow(author_with_perm).to receive(:has_permission?).with("catalogs.approve").and_return(true)

      result = described_class.new(document: catalog, actor: author_with_perm).approve!

      expect(result).not_to be_success
      expect(result.status_code).to eq(:forbidden)
      expect(catalog.reload.approval_status).to eq("pending_review")
    end

    it "lets a non-admin with the *.approve permission approve someone else's submission" do
      other = create(:user)
      allow(other).to receive(:admin?).and_return(false)
      allow(other).to receive(:has_permission?).with("catalogs.approve").and_return(true)

      result = described_class.new(document: catalog, actor: other).approve!

      expect(result).to be_success
      expect(catalog.reload.approval_status).to eq("approved")
    end

    it "rejects approving a document that is not pending review" do
      catalog.mark_approved!(approver)
      result = described_class.new(document: catalog, actor: approver).approve!

      expect(result).not_to be_success
      expect(result.status_code).to eq(:conflict)
    end
  end

  describe "#reject!" do
    before { catalog.submit_for_review!(author) }

    it "rejects with a reason (admin)" do
      result = described_class.new(document: catalog, actor: approver).reject!(reason: "Controls incomplete")

      expect(result).to be_success
      expect(catalog.reload.approval_status).to eq("rejected")
      expect(catalog.rejection_reason).to eq("Controls incomplete")
    end

    it "requires a reason" do
      result = described_class.new(document: catalog, actor: approver).reject!(reason: " ")

      expect(result).not_to be_success
      expect(result.status_code).to eq(:unprocessable_entity)
    end

    it "lets a rejected document be resubmitted" do
      described_class.new(document: catalog, actor: approver).reject!(reason: "fix it")
      result = described_class.new(document: catalog, actor: author).submit_for_review!

      expect(result).to be_success
      expect(catalog.reload.approval_status).to eq("pending_review")
      expect(catalog.rejection_reason).to be_nil
    end
  end
end
