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
    when "simple_tls" then { method: :simple_tls }
    when "start_tls"  then { method: :start_tls }
    else nil
    end

    Net::LDAP.new(
      host: SparcConfig.ldap_host,
      port: SparcConfig.ldap_port,
      encryption: encryption,
      auth: auth
    )
  end
end
