# frozen_string_literal: true

# Content-Security-Policy (CSP) header configuration.
#
# Enforced as of v1.7.0 (#514). All inline <script> blocks across app/views
# carry a nonce="<%= content_security_policy_nonce %>" attribute; the
# nonce-generator below injects matching nonce-<value> into the script-src
# directive at request time. Pages without nonce'd inline scripts have no
# inline JS to begin with, so they're unaffected by the enforce flip.
#
# Deferred to follow-up #528 (post-v1.7.0):
#   - Remove 'unsafe-inline' from style-src (Bootstrap inline-style refactor)
#   - Refactor remaining inline scripts into Stimulus controllers / ES modules
#   - Add report-uri / report-to + collector backend
#   - Trusted Types adoption
#
# References:
#   NIST SP 800-53  SC-8, SC-18
#   OWASP CSP Cheat Sheet
#   https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self, "https://cdn.jsdelivr.net"
    policy.style_src   :self, :unsafe_inline, "https://cdn.jsdelivr.net"
    policy.font_src    :self, :data, "https://cdn.jsdelivr.net"
    policy.img_src     :self, :data, :https
    policy.connect_src :self
    policy.object_src  :none
    policy.frame_ancestors :self
    policy.base_uri    :self
    # Strict 'self' globally. The login page relaxes this per-controller to
    # allow OAuth POST-redirects to enabled IdPs — see #593 and
    # SessionsController#new (SparcConfig.oauth_form_action_origins).
    policy.form_action :self

    # Violation reporting (#528, epic #650). Browsers POST a report to this
    # same-origin endpoint whenever a directive is violated, so CSP breakage
    # becomes self-surfacing telemetry instead of a silent per-user console
    # error. report-uri is exempt from connect-src. The newer Reporting-API
    # report-to (with a Reporting-Endpoints header) is tracked in #528.
    policy.report_uri "/security/csp-violations"
  end

  # Per-request random nonce (#514). The previous generator used
  # request.session.id.to_s — predictable and shared across requests in
  # the same session, which weakens CSP: an attacker who learns the
  # session id can craft inline scripts that the nonce-allowlist accepts.
  # SecureRandom.base64(16) produces a fresh 128-bit nonce per request.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Enforcing mode as of v1.7.0 (#514). Violations are now BLOCKED, not
  # just reported. All inline <script> tags in app/views carry a matching
  # nonce attribute via content_security_policy_nonce; pages without
  # inline scripts have no script-src risk to begin with.
  config.content_security_policy_report_only = false
end
