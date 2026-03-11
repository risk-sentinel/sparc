# frozen_string_literal: true

# Content-Security-Policy (CSP) header configuration.
#
# Deployed in **report-only** mode so violations are logged to the browser
# console without breaking existing functionality.  Switch to enforcing mode
# once the policy is validated in staging/production:
#
#   config.content_security_policy_report_only = false
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
    policy.form_action :self
  end

  # Generate a nonce for inline scripts that use the Rails nonce helper.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Report-only mode — violations are logged but not blocked.
  config.content_security_policy_report_only = true
end
