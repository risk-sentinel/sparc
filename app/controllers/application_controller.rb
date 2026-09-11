class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include Auditable

  # Register custom flash types so `redirect_to path, success: "msg"` works
  add_flash_types :success, :error, :warning

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # #978 — a CSRF rejection must never be silent.
  #
  # On a production-mode container reached over plain HTTP, `force_ssl` makes
  # Rails build `request.base_url` as https://…, while the browser sends
  # `Origin: http://…`. They disagree, forgery protection raises, and the 422
  # that results is SWALLOWED BY TURBO — the form re-renders with nothing on
  # screen, which is indistinguishable from a wrong password. The owner hit
  # exactly this during #974 testing and reported being unable to sign in with
  # correct credentials.
  #
  # `curl` does not reproduce it: curl sends no Origin header, so the check
  # never runs and the login succeeds. Verifying credentials with curl proves
  # nothing about whether a browser can sign in, and that false negative sent
  # the first round of diagnosis after the credentials rather than the scheme.
  #
  # Handled here rather than in SessionsController so EVERY browser form stops
  # failing silently, not just login. API controllers inherit from
  # ActionController::API and have no forgery protection at all, so they are
  # unaffected. NIST SC-8, SC-23.
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_authenticity_token

  before_action :require_authentication
  before_action :check_session_timeout
  before_action :check_password_reset
  before_action :check_webauthn_enrollment  # #802 — mandatory FIDO2 enrollment gate
  before_action :check_required_auth_method # #805 — require OIDC/PIV (phishing-resistant) auth

  # Convert a control ID to the OSCAL canonical form catalogs store.
  #
  # #911 — this was a private reimplementation of ControlId.canonical (#852)
  # that had drifted, and was wrong in four ways. It disagreed on:
  #
  #   "AC-2 (1)"        -> "ac-2-.1"        (should be "ac-2.1")
  #   "CCI-000213"      -> "cci-213"        (should be "cci-000213")
  #   "ac-19.4.(b).(1)" -> "ac-19.4..b..1"  (should be "ac-19.4.b.1")
  #
  # The first case is the NIST publication form — the most common way a person
  # writes an enhancement — so the catalog-guidance lookups in the SSP and SAR
  # views silently found nothing for it. The second corrupted fixed-width
  # external identifiers, which is exactly what ControlId's padding guard
  # exists to prevent.
  #
  # Kept as a helper_method under its original name because the SSP and SAR
  # views call it; it now delegates rather than duplicating.
  def normalize_ctrl_id(id) = ControlId.canonical(id)
  helper_method :normalize_ctrl_id

  private

  # ── CSRF failure, made visible (#978) ─────────────────────────────────

  # A 303 redirect, never a 422 render: Turbo follows a redirect and paints the
  # flash, and swallows a 422. `error` is registered in
  # ApplicationHelper::FLASH_CLASSES — a key absent there renders NOWHERE,
  # silently, which is the trap #902 exists to prevent and would have reproduced
  # this bug in a new costume.
  def handle_invalid_authenticity_token
    Rails.logger.warn(
      "[CSRF] rejected #{request.request_method} #{request.path} — " \
      "Origin=#{request.origin.inspect} base_url=#{request.base_url.inspect}"
    )

    redirect_back fallback_location: login_path, status: :see_other,
                  error: csrf_failure_message
  end

  def csrf_failure_message
    if csrf_scheme_mismatch?
      "This instance is configured for #{request.base_url}, but you reached it " \
      "over #{request.protocol.delete_suffix('://')}. The browser's security check rejected the form " \
      "before your details were read — this is NOT a wrong password. " \
      "Sign in at #{request.base_url}#{request.path} instead."
    else
      "Your session expired before this form was submitted, so it was rejected " \
      "for your safety. Please sign in again and retry."
    end
  end

  # True only for the same host and port over a different scheme — the http-vs-
  # https trap above. A genuine cross-site origin falls through to the generic
  # message, and the offending origin is never echoed back into the page: it is
  # attacker-controlled, and the person who needs it is reading the log.
  def csrf_scheme_mismatch?
    origin = request.origin
    return false if origin.blank? || origin == "null"

    sent = URI.parse(origin)
    ours = URI.parse(request.base_url)
    return false unless sent.host == ours.host

    sent.scheme != ours.scheme || sent.port != ours.port
  rescue URI::InvalidURIError
    false
  end

  # Merge metadata_extra JSON from form params into permitted params.
  # The form submits metadata_extra as a JSON string; we parse it and
  # merge into the permitted hash so ActiveRecord stores it as jsonb.
  def merge_metadata_extra(permitted, param_key)
    raw = params.dig(param_key, :metadata_extra_json)
    if raw.present?
      parsed = JSON.parse(raw)
      # Only allow known OSCAL metadata keys
      allowed = parsed.slice(*OscalMetadata::METADATA_EXTRA_KEYS)
      permitted[:metadata_extra] = (permitted[:metadata_extra] || {}).merge(allowed)
    end
    permitted
  rescue JSON::ParserError
    permitted
  end
end
