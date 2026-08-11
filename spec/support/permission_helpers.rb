# frozen_string_literal: true

# #919 — grant a permission to a user in a spec.
#
# Before the authorization sweep, most request specs signed in as a bare
# `create(:user)` and passed, because the controllers under test had no guard at
# all. Once the guards landed those specs began failing with a 302 to root, which
# is the guard working. Granting the permission the action legitimately requires
# is the correct repair — the specs are being brought in line with the real
# authorization model, not relaxed around it.
#
# Deliberately NOT a blanket "make this user an admin" helper. `admin?`
# short-circuits `User#has_permission?` entirely, so signing in as an admin would
# make every one of these specs pass without exercising the permission at all —
# and would keep passing if the guard were later removed. Granting the specific
# key keeps the spec honest about what it needs.
module PermissionHelpers
  # Grants `key` (e.g. "poam.write") to `user`.
  #
  # Pass `authorization_boundary:` for a boundary-scoped grant; omit it for an
  # instance-level one. The distinction matters: `User#has_permission?` matches a
  # boundary-scoped query against roles held on that boundary OR instance-wide,
  # but an instance-level query matches only instance-scoped roles.
  def grant_permission(user, key, authorization_boundary: nil)
    scope = authorization_boundary ? "authorization_boundary" : "instance"
    role = Role.find_or_create_by!(name: "spec_#{key.tr('.', '_')}_#{scope}") do |r|
      r.display_name = "Spec grant: #{key} (#{scope})"
      r.scope = scope
      r.permissions = {}
    end
    role.update!(permissions: role.permissions.merge(key => true))

    UserRole.find_or_create_by!(
      user: user, role: role,
      authorization_boundary_id: authorization_boundary&.id
    )
    user
  end

  # Convenience for the common case: a user who may write POA&M content on the
  # boundary owning `document`.
  def grant_document_permission(user, key, document)
    grant_permission(user, key, authorization_boundary: document.authorization_boundary)
  end
end

RSpec.configure do |config|
  config.include PermissionHelpers, type: :request
  config.include PermissionHelpers, type: :system
end
