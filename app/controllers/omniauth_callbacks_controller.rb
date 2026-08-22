# frozen_string_literal: true

# Handles OAuth/OIDC callbacks from GitHub, GitLab, and generic OIDC
# providers. Finds or creates a User by email, links an Identity, and
# establishes a session.
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (multi-provider SSO)
#   IA-8 Identification and Authentication (Non-Organizational Users)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class OmniauthCallbacksController < ApplicationController
  skip_before_action :require_authentication, raise: false
  skip_before_action :check_password_reset, raise: false

  # CodeQL `rb/csrf-protection-disabled` (alert #8) flags this. It is
  # deliberate and cannot be otherwise: the identity provider POSTs this
  # callback from ITS origin, so no CSRF token of ours can be present in the
  # request. The forgery protection that applies here is the OAuth/OIDC `state`
  # parameter, which OmniAuth validates before this action runs.
  #
  # Scoped with `only: :create` rather than skipped controller-wide, so a
  # state-changing action added to this controller later does not silently
  # inherit the exemption.
  skip_before_action :verify_authenticity_token, only: :create

  # POST /auth/:provider/callback
  def create
    auth = request.env["omniauth.auth"]

    if auth.blank?
      redirect_to login_path, error: "Authentication data missing."
      return
    end

    identity = Identity.from_omniauth(auth)
    email = (auth.info&.email || identity.email).to_s.downcase.strip

    if email.blank?
      redirect_to login_path, error: "No email returned from #{auth.provider}. Please ensure your email is public."
      return
    end

    user = identity.user || User.find_by("LOWER(email) = ?", email)

    if user.nil?
      # Auto-create user from OAuth — no password needed
      user = User.new(
        email: email,
        display_name: auth.info&.name,
        first_name: auth.info&.first_name,
        last_name: auth.info&.last_name,
        avatar_url: auth.info&.image,
        status: "active"
      )

      unless user.save
        redirect_to login_path, error: "Could not create account: #{user.errors.full_messages.to_sentence}"
        return
      end
    end

    unless user.active?
      redirect_to login_path, error: "Your account is not active. Contact an administrator."
      return
    end

    # Link identity to user
    identity.user = user
    identity.email = email
    identity.auth_data = auth.to_h.except("credentials")
    identity.save!
    identity.touch_last_used!

    start_session(user, ip_address: request.remote_ip, provider: auth.provider.to_s)
    record_piv_assertion(auth)

    AuditEvent.log(
      user: user,
      action: "login_success",
      provider: auth.provider,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: { uid: auth.uid }
    )

    sync_idp_entitlements(user, auth)

    redirect_to (session.delete(:return_to) || root_path), success: "Signed in with #{auth.provider.to_s.titleize}."
  end

  # #822 — an OIDC token can prove a smart card was used at the IdP.
  #
  # Recorded AFTER start_session, which resets the session: writing it before
  # would put the assertion into a session that is then thrown away, and the
  # requirement would silently fail for every user.
  #
  # The assertion is stored rather than folded into `auth_provider` so the audit
  # trail keeps saying the person signed in with oidc, while the auth-method
  # gate can still see that it satisfied piv. Conflating the two would lose the
  # record of which IdP the assertion actually came from.
  def record_piv_assertion(auth)
    return unless auth.provider.to_s == "oidc"
    return unless SparcConfig.piv_oidc_enabled?

    assertion = PivOidcAssertion.new(auth)
    return unless assertion.satisfied?

    session[:piv_assertion] = assertion.evidence
    AuditEvent.log(user: current_user || User.find_by(id: session[:user_id]),
                   action: "piv_asserted_by_idp", provider: "oidc",
                   ip_address: request.remote_ip, metadata: assertion.evidence)
  end

  # #860 — the login IS the sync. Entitlements are resolved from the claim on
  # every sign-in, which is what makes "a login establishes the user's rights"
  # true, and what bounds how long a revoked entitlement is still honoured
  # (together with the absolute session cap, #1043).
  #
  # Runs AFTER start_session on purpose. Sign-in has already succeeded by this
  # point, and a failure here must not undo it.
  def sync_idp_entitlements(user, auth)
    # OIDC only. GitHub and GitLab carry no grants claim, and asking them for
    # one would report every user as having an absent claim on every login.
    return unless auth.provider.to_s == "oidc"
    return if SparcConfig.oidc_sync_mode == "off"

    claims = IdpClaimReader.new(auth).read
    plan = EntitlementSync.new(user: user, claim_values: claims.values,
                               claim_present: claims.present?).apply

    Rails.logger.info("[EntitlementSync] #{user.email}: #{plan.summary}")
    log_sync_problem(user, plan) if plan.error? || plan.blocked?
    warn_about_unmatched(plan)
  rescue StandardError => e
    # A sync failure must not deny a user their session: they authenticated
    # successfully, and refusing the login would turn an entitlement bug into an
    # outage. They keep the entitlements they already had — stale, not elevated,
    # because nothing was applied.
    #
    # Recorded rather than swallowed. A silent rescue here would hide the exact
    # misconfiguration this feature is most likely to hit.
    Rails.logger.error("[EntitlementSync] #{user.email}: #{e.class}: #{e.message}")
    AuditEvent.log(user: user, action: "idp_sync_failed", provider: "oidc",
                   ip_address: request.remote_ip,
                   metadata: { error: e.class.name, message: e.message })
  end

  # A user whose grants name something SPARC does not have signs in with the
  # access that DID resolve — which may be none at all. Landing in an empty
  # SPARC with no explanation reads as a broken product, so say something.
  #
  # Deliberately vague: the grant strings name organizations and boundaries the
  # user may have no business knowing exist, and "sparc:boundary:acme:acme-prod:isso
  # was refused" tells an attacker the estate's shape. The detail goes to the
  # administrator, through the audit trail and the unmatched-grant queue.
  def warn_about_unmatched(plan)
    return if plan.unmatched.empty?

    flash[:warning] = "Some of your access could not be granted yet. " \
                      "An administrator has been notified."
  end

  def log_sync_problem(user, plan)
    reason = plan.error || plan.blocked_reason
    Rails.logger.warn("[EntitlementSync] #{user.email}: #{reason}")
    AuditEvent.log(user: user, action: "idp_sync_failed", provider: "oidc",
                   ip_address: request.remote_ip, metadata: { reason: reason })
  end

  # GET /auth/failure
  def failure
    message = params[:message] || "Unknown error"
    AuditEvent.log(
      action: "login_failure",
      provider: params[:strategy] || "unknown",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: { error: message }
    )

    redirect_to login_path, error: "Authentication failed: #{message.humanize}"
  end
end
