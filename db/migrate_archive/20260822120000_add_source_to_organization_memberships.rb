# frozen_string_literal: true

# #860 — distinguish an organization membership an IdP granted from one an
# administrator assigned deliberately. Mirrors AddSourceToUserRoles (#707/#919),
# which drew the same line for boundary-scoped roles.
#
# Without this, `authoritative` sync could not tell the two apart, and the
# guarantee the entitlement design rests on — that only rows the sync created
# are ever revoked — would hold for boundary grants and be silently false for
# organization grants. A safety property that is true in one half of a feature
# is not a safety property.
#
# It matters more here than it did for user_roles, because
# organization_memberships is UNIQUE on (organization_id, user_id): a user holds
# exactly one role per organization, so an IdP grant does not add alongside an
# existing role, it REPLACES it. Knowing which rows the IdP owns is what lets
# the sync refuse to overwrite an administrator's deliberate assignment instead
# of quietly winning.
#
# Schema-only and fast: a defaulted column, so existing rows are correct by
# construction — every membership that predates this was assigned by hand,
# because nothing else could create one.
class AddSourceToOrganizationMemberships < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:organization_memberships, :source)

    add_column :organization_memberships, :source, :string, default: "manual", null: false

    add_index :organization_memberships, :source, if_not_exists: true
  end
end
