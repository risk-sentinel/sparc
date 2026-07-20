# frozen_string_literal: true

# LDAP authentication service using bind-and-search via the net-ldap gem.
#
# Flow:
#   1. Bind with service account (SPARC_LDAP_BIND_DN / SPARC_LDAP_BIND_PASSWORD)
#   2. Search for user by SPARC_LDAP_ATTRIBUTE (default: "uid")
#   3. Attempt bind with found DN + user-provided password
#   4. Return user attributes on success, nil on failure
#
# Usage:
#   result = LdapAuthService.authenticate("jdoe", "s3cret")
#   result # => { dn: "uid=jdoe,...", email: "jdoe@example.com", ... } or nil
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (LDAP bind-and-search)
#   IA-5 Authenticator Management (directory-based credential validation)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class LdapAuthService
  class LdapError < StandardError; end

  def self.authenticate(username, password)
    new.authenticate(username, password)
  end

  def authenticate(username, password)
    return nil if username.blank? || password.blank?
    return nil unless SparcConfig.enable_ldap?

    # Step 1: Service-account bind
    ldap = build_connection(
      auth: {
        method: :simple,
        username: SparcConfig.ldap_bind_dn,
        password: SparcConfig.ldap_bind_password
      }
    )

    unless ldap.bind
      Rails.logger.error("[LDAP] Service account bind failed: #{ldap.get_operation_result.message}")
      return nil
    end

    # Step 2: Search for user
    filter = Net::LDAP::Filter.eq(SparcConfig.ldap_attribute, username)
    entry = ldap.search(base: SparcConfig.ldap_base, filter: filter, size: 1)&.first

    unless entry
      Rails.logger.info("[LDAP] User not found: #{username}")
      return nil
    end

    # Step 3: User bind (authenticate)
    user_ldap = build_connection(
      auth: {
        method: :simple,
        username: entry.dn,
        password: password
      }
    )

    unless user_ldap.bind
      Rails.logger.info("[LDAP] Authentication failed for: #{username}")
      return nil
    end

    # Step 4: Return user attributes
    {
      dn: entry.dn,
      email: entry[:mail]&.first,
      display_name: entry[:displayname]&.first || entry[:cn]&.first,
      first_name: entry[:givenname]&.first,
      last_name: entry[:sn]&.first,
      username: username
    }
  rescue Net::LDAP::Error => e
    Rails.logger.error("[LDAP] Connection error: #{e.message}")
    nil
  end

  private

  def build_connection(auth:)
    encryption = case SparcConfig.ldap_encryption
    when "simple_tls" then { method: :simple_tls, tls_options: tls_options }
    when "start_tls"  then { method: :start_tls, tls_options: tls_options }
    else nil
    end

    Net::LDAP.new(
      host: SparcConfig.ldap_host,
      port: SparcConfig.ldap_port,
      encryption: encryption,
      auth: auth
    )
  end

  # TLS options for the LDAPS / STARTTLS connection.
  #
  # NIST SC-8 (Transmission Confidentiality & Integrity) / IA-2: net-ldap only
  # applies SSLContext#set_params — and thus VERIFY_PEER — when tls_options is
  # NON-EMPTY. Omitting it (the historical behavior) yields a bare SSLContext
  # that defaults to VERIFY_NONE, so the channel is encrypted but the directory
  # server's certificate is never authenticated, leaving LDAP bind credentials
  # open to an active on-path attacker. We therefore always pass an explicit
  # verify_mode.
  #
  # Default: VERIFY_PEER against the system trust store (which picks up any CA
  # injected via the container custom-CA mechanism, #774). SPARC_LDAP_CA_FILE
  # supplies a directory CA out-of-band. SPARC_LDAP_TLS_VERIFY=false opts out
  # for legacy internal directories — insecure, and logged loudly.
  def tls_options
    unless SparcConfig.ldap_tls_verify?
      Rails.logger.warn(
        "[LDAP] TLS certificate verification is DISABLED " \
        "(SPARC_LDAP_TLS_VERIFY=false). The directory server certificate is " \
        "NOT authenticated — the connection is vulnerable to an active " \
        "man-in-the-middle. Do not use this in production."
      )
      return { verify_mode: OpenSSL::SSL::VERIFY_NONE }
    end

    options = { verify_mode: OpenSSL::SSL::VERIFY_PEER }
    options[:ca_file] = SparcConfig.ldap_ca_file if SparcConfig.ldap_ca_file.present?
    options
  end
end
