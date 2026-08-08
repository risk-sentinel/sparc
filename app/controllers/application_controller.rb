class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include Auditable

  # Register custom flash types so `redirect_to path, success: "msg"` works
  add_flash_types :success, :error, :warning

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

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
