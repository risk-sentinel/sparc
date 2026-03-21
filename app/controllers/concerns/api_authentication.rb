# Bearer token authentication for API endpoints.
#
# Supports two authentication methods:
#
# 1. SPARC API tokens (sparc_<hex>) — app-issued, SHA-256 digested
# 2. OIDC JWT tokens (eyJhbG...) — validated against the OIDC provider's
#    JWKS endpoint when SPARC_OIDC_ISSUER_URL is configured
#
# Backward-compatible: skips authentication entirely when no auth
# methods are enabled (SparcConfig.any_auth_enabled? == false).
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Organizational Users)
#   IA-5 Authenticator Management (SHA-256 token digest, JWT signature verification)
#   IA-8 Non-Organizational User Identification (OIDC JWT federation)
#   SC-13 Cryptographic Protection (secure token generation, RS256 JWT verification)
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

    # Try SPARC API token first (sparc_ prefix), then OIDC JWT
    if token_string.start_with?("sparc_")
      authenticate_sparc_token!(token_string)
    elsif SparcConfig.enable_oidc? && token_string.match?(/\Aey[A-Za-z0-9]/)
      authenticate_oidc_jwt!(token_string)
    else
      authenticate_sparc_token!(token_string)
    end
  end

  def authenticate_sparc_token!(token_string)
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

  def authenticate_oidc_jwt!(token_string)
    claims = decode_oidc_jwt(token_string)
    if claims.nil?
      render json: { error: "Invalid or expired OIDC token" }, status: :unauthorized
      return
    end

    # Look up user by email claim (preferred) or sub claim
    email = claims["email"] || claims["sub"]
    @current_user = User.find_by(email: email)

    if @current_user.nil?
      render json: { error: "No SPARC user account found for OIDC identity" }, status: :unauthorized
      return
    end

    unless @current_user.active?
      render json: { error: "User account is not active" }, status: :unauthorized
    end
  end

  def decode_oidc_jwt(token_string)
    issuer_url = SparcConfig.oidc_issuer_url
    audience = ENV.fetch("SPARC_API_OIDC_AUDIENCE", SparcConfig.oidc_client_id)

    jwks = fetch_oidc_jwks(issuer_url)
    return nil if jwks.nil?

    decoded = JWT.decode(
      token_string,
      nil,
      true,
      {
        algorithms: [ "RS256" ],
        iss: issuer_url,
        verify_iss: true,
        aud: audience,
        verify_aud: true,
        jwks: jwks
      }
    )

    decoded.first # returns the claims hash
  rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::InvalidIssuerError,
         JWT::InvalidAudError, JWT::VerificationError => e
    Rails.logger.warn("OIDC JWT validation failed: #{e.class} — #{e.message}")
    nil
  end

  def fetch_oidc_jwks(issuer_url)
    # In-memory cache with 1-hour TTL to avoid per-request HTTP calls
    cache_key = "oidc_jwks_#{Digest::SHA256.hexdigest(issuer_url)}"
    cached = Thread.current[cache_key]

    if cached && cached[:fetched_at] > 1.hour.ago
      return cached[:jwks]
    end

    discovery_url = "#{issuer_url.chomp('/')}/.well-known/openid-configuration"
    discovery_response = Net::HTTP.get(URI(discovery_url))
    discovery = JSON.parse(discovery_response)
    jwks_uri = discovery["jwks_uri"]

    return nil if jwks_uri.blank?

    jwks_response = Net::HTTP.get(URI(jwks_uri))
    jwks_data = JSON.parse(jwks_response)
    jwks = JWT::JWK::Set.new(jwks_data)

    Thread.current[cache_key] = { jwks: jwks, fetched_at: Time.current }
    jwks
  rescue StandardError => e
    Rails.logger.warn("Failed to fetch OIDC JWKS: #{e.class} — #{e.message}")
    nil
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
