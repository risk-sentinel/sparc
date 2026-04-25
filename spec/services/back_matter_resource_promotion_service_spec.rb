require "rails_helper"

RSpec.describe BackMatterResourcePromotionService do
  let(:boundary)    { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }
  let(:ssp)         { create(:ssp_document, authorization_boundary: boundary) }
  let(:resource) do
    BackMatterResource.create!(resourceable: ssp, title: "Policy", uuid: SecureRandom.uuid,
                               source: "managed")
  end

  def role_for(name, scope: "instance")
    Role.find_or_create_by!(name: name) do |r|
      r.display_name = name.titleize
      r.scope = scope
      r.permissions = {}
    end
  end

  def user_with_role(name, boundary_id: nil)
    user = create(:user)
    role = role_for(name, scope: boundary_id ? "authorization_boundary" : "instance")
    UserRole.create!(user: user, role: role, authorization_boundary_id: boundary_id)
    user
  end

  describe "#request_promotion!" do
    let(:requester) { create(:user) }

    it "transitions none → pending_review and writes a change row" do
      result = described_class.new(resource: resource, actor: requester).request_promotion!

      expect(result).to be_success
      expect(resource.reload.promotion_status).to eq("pending_review")
      expect(resource.changes_log.where(change_type: "promote").count).to eq(1)
    end

    it "is idempotent against already-pending requests" do
      resource.update!(promotion_status: "pending_review")
      result = described_class.new(resource: resource, actor: requester).request_promotion!

      expect(result).not_to be_success
      expect(result.status_code).to eq(:conflict)
    end

    it "rejects already-authoritative resources" do
      resource.update!(source: "authoritative", globally_available: true,
                       promotion_status: "approved")
      result = described_class.new(resource: resource, actor: requester).request_promotion!

      expect(result).not_to be_success
      expect(result.error).to match(/already authoritative/i)
    end

    it "allows re-request after rejection" do
      resource.update!(promotion_status: "rejected", rejection_reason: "incomplete")
      result = described_class.new(resource: resource, actor: requester).request_promotion!

      expect(result).to be_success
      expect(resource.reload.promotion_status).to eq("pending_review")
    end
  end

  describe "#approve!" do
    let(:admin) { create(:user, :admin) }

    before { resource.update!(promotion_status: "pending_review") }

    it "promotes resource to authoritative + globally_available with admin actor" do
      result = described_class.new(resource: resource, actor: admin).approve!

      expect(result).to be_success
      resource.reload
      expect(resource.promotion_status).to eq("approved")
      expect(resource.source).to eq("authoritative")
      expect(resource.globally_available).to eq(true)
      expect(resource.approved_by_user).to eq(admin)
      expect(resource.approved_at).to be_present
      expect(resource.promoted_from_authorization_boundary_id).to eq(boundary.id)
    end

    it "writes a change row per mutated field, sharing a batch_uuid" do
      described_class.new(resource: resource, actor: admin).approve!

      changes = resource.changes_log.where(change_type: "approve")
      expect(changes.pluck(:field)).to match_array(%w[promotion_status source globally_available])
      expect(changes.pluck(:batch_uuid).uniq.size).to eq(1)
    end

    it "rejects approval when not pending_review" do
      resource.update!(promotion_status: "none")
      result = described_class.new(resource: resource, actor: admin).approve!

      expect(result).not_to be_success
      expect(result.status_code).to eq(:conflict)
    end

    it "rejects approval from a non-authorized user" do
      bystander = create(:user)
      result = described_class.new(resource: resource, actor: bystander).approve!

      expect(result).not_to be_success
      expect(result.status_code).to eq(:forbidden)
    end

    it "allows approval by policy_manager" do
      policy_user = user_with_role("policy_manager")
      result = described_class.new(resource: resource, actor: policy_user).approve!

      expect(result).to be_success
    end

    it "allows approval by AO of the resource boundary" do
      ao_user = user_with_role("ao", boundary_id: boundary.id)
      result = described_class.new(resource: resource, actor: ao_user).approve!

      expect(result).to be_success
    end

    it "allows approval by agency_ao on the resource boundary" do
      agency_ao = user_with_role("agency_ao", boundary_id: boundary.id)
      result = described_class.new(resource: resource, actor: agency_ao).approve!

      expect(result).to be_success
    end

    it "allows approval by so_iso on the resource boundary" do
      so_iso = user_with_role("so_iso", boundary_id: boundary.id)
      result = described_class.new(resource: resource, actor: so_iso).approve!

      expect(result).to be_success
    end

    it "rejects approval by AO of a different boundary" do
      other_ao = user_with_role("ao", boundary_id: other_boundary.id)
      result = described_class.new(resource: resource, actor: other_ao).approve!

      expect(result).not_to be_success
      expect(result.status_code).to eq(:forbidden)
    end

    it "rejects boundary-role approval for library resources without a parent doc" do
      library = BackMatterResource.create!(resourceable: nil, title: "Library",
                                           uuid: SecureRandom.uuid, source: "managed",
                                           promotion_status: "pending_review")
      ao_user = user_with_role("ao", boundary_id: boundary.id)
      result = described_class.new(resource: library, actor: ao_user).approve!

      expect(result).not_to be_success
      expect(result.status_code).to eq(:forbidden)
    end

    it "still allows admin to approve library resources without a parent" do
      library = BackMatterResource.create!(resourceable: nil, title: "Library",
                                           uuid: SecureRandom.uuid, source: "managed",
                                           promotion_status: "pending_review")
      result = described_class.new(resource: library, actor: admin).approve!

      expect(result).to be_success
    end
  end

  describe "#reject!" do
    let(:admin) { create(:user, :admin) }

    before { resource.update!(promotion_status: "pending_review") }

    it "transitions pending_review → rejected with reason" do
      result = described_class.new(resource: resource, actor: admin).reject!(reason: "needs more detail")

      expect(result).to be_success
      resource.reload
      expect(resource.promotion_status).to eq("rejected")
      expect(resource.rejection_reason).to eq("needs more detail")
      expect(resource.changes_log.where(change_type: "reject").count).to eq(2)
    end

    it "requires a non-blank reason" do
      result = described_class.new(resource: resource, actor: admin).reject!(reason: "  ")

      expect(result).not_to be_success
      expect(result.status_code).to eq(:unprocessable_entity)
    end

    it "rejects when not pending_review" do
      resource.update!(promotion_status: "approved")
      result = described_class.new(resource: resource, actor: admin).reject!(reason: "x")

      expect(result).not_to be_success
      expect(result.status_code).to eq(:conflict)
    end
  end

  describe "#can_approve?" do
    it "returns false for nil user" do
      expect(described_class.new(resource: resource, actor: nil).can_approve?).to eq(false)
    end
  end
end
