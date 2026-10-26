# frozen_string_literal: true

# OmniAuth configuration — providers are registered conditionally based
# on SparcConfig toggles and environment variables. Only providers with
# valid credentials are registered.
#
# All OmniAuth routes require POST (via omniauth-rails_csrf_protection)
# to prevent CSRF attacks on the login flow.

# NIST 800-53: IA-8, SC-23. OAuth providers (GitHub, GitLab) send the IdP a
# callback URL that OmniAuth builds from the request's Host, X-Forwarded-Host or
# Forwarded header, which a client can forge (GHSA-m27g-v28p-f9fx). Build it
# from SPARC_APP_URL instead (SparcConfig.oauth_full_host): the same setting the
# OIDC redirect URI, WebAuthn origin and mailer links already use. Without it
# the behaviour is unchanged and OmniAuth logs a warning on each sign-in.
# after_initialize: initializers run before app/models autoloads SparcConfig.
Rails.application.config.after_initialize do
  host = SparcConfig.oauth_full_host
  OmniAuth.config.full_host = host if host
end

Rails.application.config.middleware.use OmniAuth::Builder do
  # ── GitHub OAuth ──────────────────────────────────────────────────────
  if SparcConfig.github_enabled?
    provider :github,
             SparcConfig.github_client_id,
             SparcConfig.github_client_secret,
             scope: "user:email"
  end

  # ── GitLab OAuth ─────────────────────────────────────────────────────
  if SparcConfig.gitlab_enabled?
    provider :gitlab,
             SparcConfig.gitlab_client_id,
             SparcConfig.gitlab_client_secret,
             client_options: { site: SparcConfig.gitlab_site }
  end

  # ── Generic OIDC (Okta, Keycloak, Entra ID, etc.) ───────────────────
  if SparcConfig.enable_oidc? && SparcConfig.oidc_issuer_url.present?
    provider :openid_connect,
             name: :oidc,
             scope: SparcConfig.oidc_scopes.split,
             issuer: SparcConfig.oidc_issuer_url,
             discovery: true,
             client_options: {
               identifier: SparcConfig.oidc_client_id,
               secret: SparcConfig.oidc_client_secret,
               redirect_uri: SparcConfig.oidc_redirect_uri
             }
  end

  # ── Failure handling ─────────────────────────────────────────────────
  on_failure do |env|
    OmniauthCallbacksController.action(:failure).call(env)
  end
end
