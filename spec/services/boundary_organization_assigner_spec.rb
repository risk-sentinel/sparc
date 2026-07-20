# frozen_string_literal: true

require "rails_helper"

# #770 bug 6 — org-assignment authorization matrix.
RSpec.describe BoundaryOrganizationAssigner do
  let(:org_a) { create(:organization) }
  let(:org_b) { create(:organization) }
  let(:admin) { create(:user, :admin) }
  let(:org_admin) do
    create(:user).tap { |u| create(:organization_membership, user: u, organization: org_a, role: "org_admin") }
  end
  let(:outsider) { create(:user) }

  def assign(boundary:, organization:, actor:)
    described_class.new(boundary: boundary, organization: organization, actor: actor).call
  end

  describe "instance admin" do
    it "assigns an unassigned boundary" do
      b = create(:authorization_boundary, organization: nil)
      expect { assign(boundary: b, organization: org_a, actor: admin) }
        .to change { b.reload.organization }.from(nil).to(org_a)
    end

    it "moves a boundary between organizations" do
      b = create(:authorization_boundary, organization: org_b)
      expect { assign(boundary: b, organization: org_a, actor: admin) }
        .to change { b.reload.organization }.from(org_b).to(org_a)
    end

    it "clears the association" do
      b = create(:authorization_boundary, organization: org_a)
      expect { assign(boundary: b, organization: nil, actor: admin) }
        .to change { b.reload.organization }.from(org_a).to(nil)
    end
  end

  describe "non-admin org_admin of the target org" do
    it "assigns an UNASSIGNED boundary into their org" do
      b = create(:authorization_boundary, organization: nil)
      expect { assign(boundary: b, organization: org_a, actor: org_admin) }
        .to change { b.reload.organization }.from(nil).to(org_a)
    end

    it "cannot MOVE a boundary that belongs to another org (instance-admin-only)" do
      b = create(:authorization_boundary, organization: org_b)
      expect { assign(boundary: b, organization: org_a, actor: org_admin) }
        .to raise_error(BoundaryOrganizationAssigner::MoveRequiresAdminError, /instance admin/)
      expect(b.reload.organization).to eq(org_b)
    end
  end

  describe "non-admin without org_admin on the target org" do
    it "cannot assign even an unassigned boundary" do
      b = create(:authorization_boundary, organization: nil)
      expect { assign(boundary: b, organization: org_a, actor: outsider) }
        .to raise_error(Authorization::NotAuthorizedError, /Not authorized/)
      expect(b.reload.organization).to be_nil
    end

    it "org_admin of a DIFFERENT org cannot assign into org_a" do
      b = create(:authorization_boundary, organization: nil)
      other_admin = create(:user).tap do |u|
        create(:organization_membership, user: u, organization: org_b, role: "org_admin")
      end
      expect { assign(boundary: b, organization: org_a, actor: other_admin) }
        .to raise_error(Authorization::NotAuthorizedError)
    end
  end

  describe "#moving_between_organizations?" do
    it "is false for a first assignment" do
      svc = described_class.new(boundary: create(:authorization_boundary, organization: nil),
                                organization: org_a, actor: admin)
      expect(svc.moving_between_organizations?).to be(false)
    end

    it "is true when the boundary already belongs to a different org" do
      svc = described_class.new(boundary: create(:authorization_boundary, organization: org_b),
                                organization: org_a, actor: admin)
      expect(svc.moving_between_organizations?).to be(true)
    end
  end
end
