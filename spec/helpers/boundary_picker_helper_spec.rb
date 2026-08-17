# frozen_string_literal: true

require "rails_helper"

# #929 — which boundaries an upload/attach form may offer.
#
# The defect this replaces: both pickers joined the LEGACY roster on
# `authorization_boundary_memberships.user_id`, a column that is optional and
# nil for any member added by name/email. Permissions and index scoping run off
# `UserRole` instead. On the demo estate every roster row had a nil user_id and
# the admin had no user_roles, so the query returned nothing for everyone and
# the field was removed from the page — no boundary could be chosen at upload
# by anybody, which is the source of #952's orphaned documents.
RSpec.describe BoundaryPickerHelper, type: :helper do
  describe "#assignable_boundaries" do
    let!(:granted_boundary)  { create(:authorization_boundary, name: "Alpha ATO") }
    let!(:rostered_boundary) { create(:authorization_boundary, name: "Bravo ATO") }
    let!(:other_boundary)    { create(:authorization_boundary, name: "Charlie ATO") }

    it "returns nothing for a signed-out render rather than raising" do
      expect(helper.assignable_boundaries(nil)).to be_empty
    end

    it "offers an Instance-Admin every boundary, including ones they hold no role on" do
      # The admin bypass in boundary_scoped_relation has no counterpart here
      # before #929: an admin who is on no roster saw NO picker at all.
      admin = create(:user, :admin)

      expect(helper.assignable_boundaries(admin))
        .to contain_exactly(granted_boundary, rostered_boundary, other_boundary)
    end

    it "offers a boundary granted through UserRole — the path permissions actually use" do
      user = create(:user)
      role = create(:role, :authorization_boundary_scoped)
      create(:user_role, user: user, role: role, authorization_boundary_id: granted_boundary.id)

      expect(helper.assignable_boundaries(user)).to contain_exactly(granted_boundary)
    end

    it "still offers a boundary reached only through a linked legacy roster row" do
      user = create(:user)
      create(:authorization_boundary_membership,
             authorization_boundary: rostered_boundary, role: "isso", user: user)

      expect(helper.assignable_boundaries(user)).to contain_exactly(rostered_boundary)
    end

    it "unions both role systems without duplicating a boundary reachable by both" do
      user = create(:user)
      role = create(:role, :authorization_boundary_scoped)
      create(:user_role, user: user, role: role, authorization_boundary_id: granted_boundary.id)
      create(:authorization_boundary_membership,
             authorization_boundary: granted_boundary, role: "isso", user: user)
      create(:authorization_boundary_membership,
             authorization_boundary: rostered_boundary, role: "isso", user: user)

      result = helper.assignable_boundaries(user)
      expect(result.to_a).to contain_exactly(granted_boundary, rostered_boundary)
      expect(result.count).to eq(2)
    end

    it "does not offer a boundary the user has no relationship to" do
      user = create(:user)
      create(:authorization_boundary_membership,
             authorization_boundary: rostered_boundary, role: "isso", user: user)

      expect(helper.assignable_boundaries(user)).not_to include(other_boundary)
    end

    it "ignores an unlinked roster row — the exact shape that returned an empty set" do
      # A roster entry created by name/email only. `user_id` is nil, so the old
      # join matched nothing even though the person is plainly on the roster.
      user = create(:user, email: "rostered@example.gov")
      create(:authorization_boundary_membership,
             authorization_boundary: rostered_boundary, role: "isso",
             user: nil, user_name: "Rostered Person", user_email: "rostered@example.gov")

      expect(helper.assignable_boundaries(user)).to be_empty
    end

    it "orders by name so the dropdown is stable" do
      admin = create(:user, :admin)

      expect(helper.assignable_boundaries(admin).map(&:name))
        .to eq([ "Alpha ATO", "Bravo ATO", "Charlie ATO" ])
    end
  end
end
