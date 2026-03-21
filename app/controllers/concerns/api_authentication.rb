# Bearer token authentication for API endpoints.
#
# Supports three mutually exclusive modes controlled by SPARC_API_AUTH:
#
# 1. local (default) — SPARC API tokens (sparc_<hex>) only
# 2. oidc            — OIDC JWT tokens only (validated via JWKS)
# 3. hybrid          — JWTs for human users + SPARC tokens for service accounts
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
    attr_reader :current_api_token, :current_auth_mode
  end

  private

  # ── Main entry point ──────────────────────────────────────────────────────

  def authenticate_api_token!
    # Backward compat: if no auth is enabled, allow anonymous access
    unless SparcConfig.any_auth_enabled?
      @current_user = User.first
      @current_auth_mode = "none"
      return
    end

    token_string = extract_bearer_token
    if token_string.blank?
      render json: { error: "Missing or invalid Authorization header. Use: Authorization: Bearer <token>" },
             status: :unauthorized
      return
    end

    case SparcConfig.api_auth_mode
    when "local"
      authenticate_local_mode!(token_string)
    when "oidc"
      authenticate_oidc_mode!(token_string)
    when "hybrid"
      authenticate_hybrid_mode!(token_string)
    else
      render json: { error: "Invalid API authentication mode configured" }, status: :internal_server_error
    end
  end

  # ── Mode dispatchers ──────────────────────────────────────────────────────

  def authenticate_local_mode!(token_string)
    if token_string.match?(/\Aey[A-Za-z0-9]/)
      render json: { error: "OIDC authentication is not enabled. Set SPARC_API_AUTH=oidc or SPARC_API_AUTH=hybrid to use JWT tokens." },
             status: :unauthorized
      return
    end

    authenticate_sparc_token!(token_string)
    @current_auth_mode = "local" if @current_user
  end

  def authenticate_oidc_mode!(token_string)
    if token_string.start_with?("sparc_")
      render json: { error: "Local token authentication is not enabled. Set SPARC_API_AUTH=local or SPARC_API_AUTH=hybrid to use SPARC tokens." },
             status: :unauthorized
      return
    end

    authenticate_oidc_jwt!(token_string)
    @current_auth_mode = "oidc" if @current_user
  end

  def authenticate_hybrid_mode!(token_string)
    if token_string.start_with?("sparc_")
      authenticate_sparc_token!(token_string)
      return unless @current_user

      unless @current_user.service_account?
        @current_user = nil
        render json: { error: "Service account token required in hybrid mode. Only service accounts can use SPARC tokens when SPARC_API_AUTH=hybrid." },
               status: :unauthorized
        return
      end

      @current_auth_mode = "service_token"
    else
      authenticate_oidc_jwt!(token_string)
      @current_auth_mode = "oidc" if @current_user
    end
  end

  # ── SPARC token authentication ────────────────────────────────────────────

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

    # AC-3: Endpoint scoping enforcement
    unless @current_api_token.endpoint_allowed?(request.path)
      render json: { error: "Token is not authorized for this endpoint" }, status: :forbidden
      @current_user = nil
      return
    end

    # AC-17: CIDR allowlist enforcement
    unless @current_api_token.cidr_allowed?(request.remote_ip)
      render json: { error: "Request IP is not in the token's allowed CIDR range" }, status: :forbidden
      @current_user = nil
    end
  end

  # ── OIDC JWT authentication ──────────────────────────────────────────────

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
    cache_key = "oidc_jwks_#{Digest::SHA256.hexdigest(issuer_url)}"

    # Use Rails.cache for multi-process safety (Puma workers, Sidekiq)
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      discovery_url = "#{issuer_url.chomp('/')}/.well-known/openid-configuration"
      discovery_response = Net::HTTP.get(URI(discovery_url))
      discovery = JSON.parse(discovery_response)
      jwks_uri = discovery["jwks_uri"]

      return nil if jwks_uri.blank?

      jwks_response = Net::HTTP.get(URI(jwks_uri))
      jwks_data = JSON.parse(jwks_response)
      JWT::JWK::Set.new(jwks_data)
    end
  rescue StandardError => e
    Rails.logger.warn("Failed to fetch OIDC JWKS: #{e.class} — #{e.message}")
    nil
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  def extract_bearer_token
    header = request.headers["Authorization"].to_s
    return nil unless header.downcase.start_with?("bearer ")

    header[7..].strip.presence
  end

  def current_user
    @current_user
  end
end
