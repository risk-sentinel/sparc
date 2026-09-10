# frozen_string_literal: true

# #1082 — refuse to start a production instance whose required sign-in methods
# cannot be used, and report the enable-vs-require posture at boot.
#
# The lockout this prevents:
#
#     SPARC_REQUIRE_AUTH_METHODS="oidc,piv"
#     # SPARC_ENABLE_PIV unset, no SPARC_OIDC_CLIENT_ID
#
# demands methods that do not exist on the instance. Every session is ended on
# the next request and redirected to a login page offering nothing that can
# satisfy the gate. It failed at REQUEST time, not boot, so it shipped green and
# locked the instance.
#
# The decision itself lives in AuthPosture, which is spec'd. This file is the
# boot-time caller and the environment policy: fatal in production, loud
# everywhere else.
#
# NIST 800-53: IA-2, IA-2(1)/(2), IA-2(8), CM-6 (configuration settings reported
# at start-up), CM-6(2) (respond to unauthorized configuration).

Rails.application.config.after_initialize do
  # `assets:precompile` boots the app purely to build assets (Rails signals that
  # build context with SECRET_KEY_BASE_DUMMY). There is no deployment to protect
  # and no auth wired there, and a hard fail would abort the image build — the
  # mistake #785 made and this skip exists to avoid.
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?
  next unless SparcConfig.require_auth_methods?

  if AuthPosture.lockout?
    # Outside production this is a half-finished configuration, not an outage —
    # and the login page says the same thing on screen (sessions/new.html.erb),
    # so a developer is not left staring at an empty box.
    raise AuthPosture.lockout_message if Rails.env.production?

    Rails.logger.error(AuthPosture.lockout_message)
  else
    Rails.logger.info(AuthPosture.summary_message)
    Rails.logger.warn(AuthPosture.partial_message) if AuthPosture.partial?
  end
end
