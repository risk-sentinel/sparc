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

Rails.application.config.after_initialize do
  # Nothing to prove against a local dev/test Postgres with no TLS at all.
  next unless Rails.env.production?
  next if ENV["SPARC_SKIP_DB_TLS_CHECK"] == "true"

  begin
    require "pg"

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

    unencrypted = results.select { |_, v| v == false }.keys
    ciphers     = results.values.grep(String).uniq

    if unencrypted.any?
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
