# frozen_string_literal: true

# #1120 — tell the operator at boot about a setting SPARC no longer reads.
#
# A retired variable left in a task definition does nothing, silently, and the
# deployment believes it is configured. SparcConfig::RETIRED_VARIABLES lists
# each one with what to do instead; this logs one warning per variable still
# set. A warning, not a failure: the variable does no harm by being there.
#
# NIST 800-53: CM-6 (configuration settings reported at start-up).

Rails.application.config.after_initialize do
  # `assets:precompile` boots the app only to build assets; there is no
  # deployment configuration to report on (see zz_auth_posture.rb).
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  SparcConfig.retired_variable_warnings.each { |message| Rails.logger.warn(message) }
end
