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

  # Convert SSP/SAR control IDs (from Excel: "AC-1", "AC-01", "AC-2(1)")
  # to the OSCAL canonical format used by catalogs:
  #   "AC-1"    → "ac-1"      "AC-01"   → "ac-1"
  #   "AC-2(1)" → "ac-2.1"    "ac-2.1"  → "ac-2.1" (already canonical)
  def normalize_ctrl_id(id)
    id.to_s.strip.downcase
      .gsub(/\s+/, "-")
      .gsub("(", ".").gsub(")", "")
      .sub(/\A([a-z]+-?)0+(\d)/) { "#{$1}#{$2}" }
  end
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
