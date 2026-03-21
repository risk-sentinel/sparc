# Bearer token authentication for API endpoints.
#
# Extracts the token from the Authorization header, authenticates it
# via ApiToken.authenticate, and sets current_user. Returns 401 JSON
# for missing/invalid/expired tokens.
#
# Backward-compatible: skips authentication entirely when no auth
# methods are enabled (SparcConfig.any_auth_enabled? == false).
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Organizational Users)
#   IA-5 Authenticator Management (SHA-256 token digest, expiry)
#   SC-13 Cryptographic Protection (secure token generation)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
module ApiAuthentication
  extend ActiveSupport::Concern

  included do
    attr_reader :current_api_token
  end

  private

  def authenticate_api_token!
    # Backward compat: if no auth is enabled, allow anonymous access
    unless SparcConfig.any_auth_enabled?
      @current_user = User.first
      return
    end

    token_string = extract_bearer_token
    if token_string.blank?
      render json: { error: "Missing or invalid Authorization header. Use: Authorization: Bearer <token>" },
             status: :unauthorized
      return
    end

    @current_api_token = ApiToken.authenticate(token_string)
    if @current_api_token.nil?
      render json: { error: "Invalid or expired API token" }, status: :unauthorized
      return
    end

    @current_user = @current_api_token.user

    unless @current_user&.active?
      render json: { error: "User account is not active" }, status: :unauthorized
      return
    end

    @current_api_token.touch_usage!(ip: request.remote_ip)
  end

  def extract_bearer_token
    header = request.headers["Authorization"].to_s
    return nil unless header.downcase.start_with?("bearer ")

    header[7..].strip.presence
  end

  def current_user
    @current_user
  end
end
