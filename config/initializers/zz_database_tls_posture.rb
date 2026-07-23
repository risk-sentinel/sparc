# frozen_string_literal: true

# #785 — report the ACTUAL database TLS posture at boot.
#
# Why this exists: the TLS floor lives in config/database.yml, which operators
# neither manage nor read — it ships inside the image. Without this, an instance
# could be running on `require` (encrypted, but the server NOT authenticated,
# which is not sufficient for FedRAMP High) and nothing would ever say so.
#
# It reports MEASURED state, not configured intent: it asks each backend via
# pg_stat_ssl rather than trusting what we wrote in the config. Same principle
# as spec/security/database_tls_spec.rb — a config value proves nothing about
# the connection that actually got made.
#
# Checks EVERY database (primary + cache/queue/cable), because the secondaries
# are precisely the ones that were unprotected: DATABASE_URL only ever applies
# to `primary`.
#
# Probes with raw PG connections rather than ActiveRecord::Base.establish_connection,
# which would swap the global connection for every model — a failure mid-loop
# could leave the app pointed at the `cable` database. Each probe connection is
# opened, read, and closed without AR's connection state being touched at all.
#
# Warns, never raises. A hard failure here would turn a transient database
# problem — or an RDS parameter-group change in flight — into a boot outage, and
# server-side enforcement (sparc-iac#566, rds.force_ssl=1) is the control that
# makes plaintext genuinely impossible.
#
# NIST 800-53: SC-8, SC-8(1), SC-13.

require "pg"

Rails.application.config.after_initialize do
  # Nothing to prove against a local dev/test Postgres with no TLS at all.
  next unless Rails.env.production?
  next if ENV.fetch("SPARC_SKIP_DB_TLS_CHECK", nil) == "true"

  begin
    mode     = SparcConfig.db_sslmode
    verified = SparcConfig.db_tls_verified?
    results  = {}

    ActiveRecord::Base.configurations
                      .configs_for(env_name: Rails.env)
                      .each do |db_config|
      cfg  = db_config.configuration_hash
      name = db_config.name

      begin
        conn = PG.connect(
          host:        cfg[:host],
          port:        cfg[:port],
          dbname:      cfg[:database],
          user:        cfg[:username],
          password:    cfg[:password],
          sslmode:     cfg[:sslmode],
          sslrootcert: cfg[:sslrootcert].presence,
          connect_timeout: 5
        )
        row = conn.exec("SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid()").first
        encrypted = row && row["ssl"] == "t"
        results[name] = encrypted ? (row["version"].presence || "TLS") : false
      rescue StandardError => e
        results[name] = "unknown (#{e.class})"
      ensure
        conn&.close
      end
    end

    next if results.empty?

    # Three states, not two. A probe that could not connect proves NOTHING about
    # encryption, and must never be folded in with the encrypted ones — an
    # earlier version did exactly that and cheerfully reported "all 4
    # connections encrypted" when all four probes had in fact failed. A security
    # diagnostic that claims safety it did not measure is worse than no
    # diagnostic at all.
    unencrypted = results.select { |_, v| v == false }.keys
    undetermined = results.select { |_, v| v.is_a?(String) && v.start_with?("unknown") }.keys
    ciphers = results.values.grep(String).reject { |v| v.start_with?("unknown") }.uniq

    if undetermined.any? && unencrypted.empty? && ciphers.empty?
      Rails.logger.warn(
        "[SPARC] DATABASE TLS: could NOT be determined for any of #{results.size} " \
        "connections (#{undetermined.join(', ')}). This is not a clean bill of health — " \
        "the probe could not connect. Verify the database is reachable and see " \
        "docs/DATABASE_TLS.md."
      )
    elsif undetermined.any?
      Rails.logger.warn(
        "[SPARC] DATABASE TLS: #{undetermined.size} of #{results.size} connections could " \
        "not be probed (#{undetermined.join(', ')}); the rest report #{ciphers.join(', ')}. " \
        "Treat the unprobed ones as unverified."
      )
    elsif unencrypted.any?
      Rails.logger.error(
        "[SPARC] ⚠️  DATABASE TLS: #{unencrypted.size} of #{results.size} connections are " \
        "NOT ENCRYPTED (#{unencrypted.join(', ')}) despite sslmode=#{mode}. Data in transit " \
        "to the database is exposed. NIST SC-8 requires encryption in transit — see " \
        "docs/DATABASE_TLS.md."
      )
    elsif !verified
      Rails.logger.warn(
        "[SPARC] DATABASE TLS: all #{results.size} connections encrypted (#{ciphers.join(', ')}), " \
        "but the server is NOT AUTHENTICATED. sslmode=#{mode} stops eavesdropping, not " \
        "impersonation. Set SPARC_DB_SSLMODE=verify-full for FedRAMP High — see " \
        "docs/DATABASE_TLS.md."
      )
    else
      Rails.logger.info(
        "[SPARC] Database TLS: #{results.size}/#{results.size} connections encrypted and " \
        "server-authenticated (sslmode=#{mode}, #{ciphers.join(', ')})."
      )
    end
  rescue StandardError => e
    # A diagnostic must never be the reason a deploy fails.
    Rails.logger.warn("[SPARC] Database TLS posture check skipped: #{e.class}: #{e.message}")
  end
end
