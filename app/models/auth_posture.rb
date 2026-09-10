# frozen_string_literal: true

# #1082 — is this instance's sign-in policy actually satisfiable?
#
# `SPARC_REQUIRE_AUTH_METHODS` (#805) is a gate: a session established by a
# method outside the allowlist is ENDED on the next request. Nothing checked
# that the required methods were usable, so a policy naming a method the
# instance does not offer locked every non-exempt account out — at REQUEST
# time, not boot, so it shipped green.
#
# The decision lives here rather than inside the initializer so it can be
# tested. `config/initializers/zz_auth_posture.rb` is the caller.
module AuthPosture
  extend self

  # What each method needs BEYOND being switched on. A requirement can turn a
  # switch on (see SparcConfig#auth_switch_enabled?); it cannot invent a
  # credential, which is why these are reported instead of inferred.
  CREDENTIALS = {
    "oidc"   => "SPARC_OIDC_CLIENT_ID",
    "sso"    => "SPARC_OIDC_CLIENT_ID",
    "github" => "SPARC_GITHUB_CLIENT_ID",
    "gitlab" => "SPARC_GITLAB_CLIENT_ID",
    "ldap"   => "SPARC_LDAP_HOST"
  }.freeze

  # Every required method is unusable: nobody but the break-glass bootstrap
  # admin and service accounts can hold a session. An outage.
  def lockout?
    SparcConfig.require_auth_methods? && SparcConfig.usable_required_auth_methods.empty?
  end

  # SOME required method works. Not a lockout — the gate is an OR, so users sign
  # in with one of the working ones — but a method nobody can choose is still a
  # misconfiguration worth saying out loud.
  def partial?
    SparcConfig.require_auth_methods? &&
      SparcConfig.usable_required_auth_methods.any? &&
      SparcConfig.unusable_required_auth_methods.any?
  end

  def lockout_message
    <<~MSG
      [SPARC] SPARC_REQUIRE_AUTH_METHODS demands a sign-in method this instance cannot offer.

        required: #{SparcConfig.required_auth_methods.join(', ')}
        usable:   (none)

      Every session established by any other method is ended on the next request,
      so this configuration locks out every account except the break-glass
      bootstrap admin and service accounts.

      Requiring a method now ENABLES it where enablement is a switch (local, ldap,
      piv, fido2). It cannot supply a credential:
      #{missing_credentials_lines}
      Set the missing configuration, or correct SPARC_REQUIRE_AUTH_METHODS.
      See docs/ENVIRONMENT_VARIABLES.md and the wiki's Authentication and MFA page.
    MSG
  end

  def partial_message
    "[SPARC] Required sign-in method(s) NOT usable on this instance: " \
    "#{SparcConfig.unusable_required_auth_methods.join(', ')}. Users can still sign in with " \
    "#{SparcConfig.usable_required_auth_methods.join(', ')}, so this is not a lockout — but the " \
    "unusable method is missing its configuration and nobody can choose it. " \
    "See docs/ENVIRONMENT_VARIABLES.md."
  end

  def summary_message
    "[SPARC] Required sign-in methods: #{SparcConfig.required_auth_methods.join(', ')} — " \
    "usable: #{SparcConfig.usable_required_auth_methods.join(', ')}."
  end

  # Name the variable the operator is actually missing, rather than making them
  # map "oidc is not usable" back to a variable name themselves.
  def missing_credentials_lines
    lines = SparcConfig.unusable_required_auth_methods.filter_map do |method|
      credential = CREDENTIALS[method]
      "        #{method.ljust(6)} also needs #{credential}" if credential
    end
    return "" if lines.empty?

    "\n#{lines.join("\n")}\n"
  end
end
