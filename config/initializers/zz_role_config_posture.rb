# frozen_string_literal: true

# #875 — report how SPARC_AUTH_BOUNDARY_ROLES was interpreted, at boot.
#
# The variable is forgiving by design: entries are resolved to built-in roles
# where they can be (case, punctuation and known labels/abbreviations all fold
# together), and anything left over is accepted as a custom role. So there is no
# such thing as an invalid value, and nothing here raises — deliberately, unlike
# zz_storage_posture.rb. A role list that an operator mistyped should not be able
# to stop a deployment from starting; access is still constrained by the roles
# that actually exist on records.
#
# What it CAN do is silently mean something other than intended: `Team Member`
# resolving to the built-in `project_member` is right, but `Assessor / Independent`
# becoming a brand-new role is a decision the operator should see rather than
# discover in a dropdown. So the resolution is logged, with custom roles called
# out separately.
#
# NIST 800-53: AC-2 (account management — role assignment), AC-3 (access
# enforcement), CM-6 (configuration settings reported at start-up).

Rails.application.config.after_initialize do
  # `assets:precompile` boots the app purely to build assets (Rails signals that
  # with SECRET_KEY_BASE_DUMMY). No deployment to report on there. See #785.
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?
  next if ENV["SPARC_AUTH_BOUNDARY_ROLES"].blank?

  configured = AuthorizationBoundaryMembership.configured_roles
  next if configured.empty?

  built_in, custom = configured.map { |entry| entry[:value] }
                               .partition { |role| AuthorizationBoundaryMembership::DEFAULT_ROLES.include?(role) }

  Rails.logger.info(
    "[SPARC] Authorization-boundary roles: #{configured.size} configured " \
    "(#{built_in.size} built-in, #{custom.size} custom) — #{configured.map { |e| e[:value] }.join(', ')}."
  )

  if custom.any?
    Rails.logger.warn(
      "[SPARC] Authorization-boundary roles not built in, accepted as custom: #{custom.join(', ')}. " \
      "If one of these was meant to be a standard role, it did not match — the built-in keys are " \
      "#{AuthorizationBoundaryMembership::DEFAULT_ROLES.join(', ')}. See docs/ENVIRONMENT_VARIABLES.md."
    )
  end
end
