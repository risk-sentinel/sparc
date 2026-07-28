# frozen_string_literal: true

require "json"
require "time"

# #785 — structured (JSON) log formatter.
#
# SPARC_STRUCTURED_LOGGING has been documented since the first version of
# docs/ENVIRONMENT_VARIABLES.md as "Output logs in JSON format (CloudWatch, ELK,
# Splunk friendly)". It was never implemented — the variable was read by nothing
# and no formatter existed. This is that implementation.
#
# Why it matters beyond tidiness: NIST 800-53 AU-3 (Content of Audit Records)
# expects records to carry what happened, when, from where, and the outcome, in a
# form that can be *queried*. Tagged plain text is greppable, not queryable — a
# log aggregator cannot filter on `request_id` when it is embedded in a string.
#
# Note this is operational logging, distinct from SPARC's AuditEvent model, which
# is the system of record for security-relevant user actions. Both matter; this
# one makes request-level tracing usable.
#
# This file lives outside the Zeitwerk-managed lib/ tree (see the `ignore:` list
# in config/application.rb) because config/application.rb has to `require` it
# directly, long before autoloading is available.
module Logging
  class SparcJsonFormatter < ::Logger::Formatter
    # Supplies #current_tags / #tagged, so tags set via config.log_tags are
    # readable as data instead of being prepended to the message as text.
    include ActiveSupport::TaggedLogging::Formatter

    # Defined after the include, so it wins over the module's tag-prepending
    # implementation. That is the whole point: tags become fields, not prefixes.
    def call(severity, timestamp, _progname, msg)
      payload = {
        ts:    timestamp.utc.iso8601(3),
        level: severity,
        msg:   stringify(msg)
      }

      tags = current_tags
      if tags.any?
        # config.log_tags = [:request_id] puts the request id first; keeping it
        # as a named field is what makes a request traceable across many lines.
        payload[:request_id] = tags.first
        payload[:tags] = tags[1..] if tags.size > 1
      end

      "#{JSON.generate(payload)}\n"
    rescue StandardError => e
      # A logger must never take the process down. If a message cannot be
      # serialised, emit a valid JSON line recording that fact instead.
      %({"ts":"#{Time.now.utc.iso8601(3)}","level":"ERROR",) +
        %("msg":"log formatting failed: #{e.class}"}\n)
    end

    private

    def stringify(msg)
      redact(
        case msg
        when String    then msg.strip
        when Exception then "#{msg.class}: #{msg.message}"
        when nil       then ""
        else msg.inspect
        end
      )
    end

    REDACTED = "[REDACTED]"

    # Credentials must never reach the log aggregator (NIST AU-9, IA-5(1)).
    #
    # Nothing here logs a password on purpose — they arrive through paths nobody
    # intends. A driver failure reports the whole connection string
    # (`PG::ConnectionBad` embeds the conninfo), and `inspect` on a resolved
    # database config hash prints every value in it. Both land in CloudWatch
    # during an ECS deployment, where a database password is then retained for
    # as long as the log group is.
    #
    # #834 is the real fix — the plaintext DATABASE_URL leaves the task
    # definition entirely. This is the backstop for everything that still
    # renders one, and it is deliberately narrow: only the secret is replaced,
    # so the host, port, user and error text all survive and the log stays
    # useful for diagnosis.
    REDACTIONS = [
      # scheme://user:password@host  ->  scheme://user:[REDACTED]@host
      [ %r{(?<prefix>[a-zA-Z][a-zA-Z0-9+.\-]*://[^:/?\#\s@]+:)[^@\s/]+@}, "\\k<prefix>#{REDACTED}@" ],
      # libpq conninfo and shell form: password=secret, PGPASSWORD=secret.
      # `(?!>)` keeps this off Ruby's `:password=>"..."` hash form, which the
      # next pattern handles — without it this one matches first and eats the
      # `>` and the quotes, leaving a mangled line.
      [ /\b(PGPASSWORD|password)=(?!>)(?:"[^"]*"|'[^']*'|\S+)/i, "\\1=#{REDACTED}" ],
      # inspected hashes: "password"=>"secret", password: "secret"
      [ /(["']?password["']?\s*(?:=>|:)\s*)(?:"[^"]*"|'[^']*')/i, "\\1\"#{REDACTED}\"" ]
    ].freeze

    # Deliberate, opt-in escape hatch for the case where the credential itself
    # is what you are debugging — "is the app even receiving the rotated
    # password?" cannot be answered from `[REDACTED]`.
    #
    # Off unless SPARC_LOG_CREDENTIALS=true, and an initializer
    # announces it loudly at boot because the consequence outlives the session:
    # anything logged while it is on is in the aggregator for the life of the
    # log group. Treat any password exposed this way as COMPROMISED and rotate
    # it afterwards — with #834 that is a Secrets Manager rotation and a task
    # restart, no redeploy.
    #
    # Read per instance rather than per line: a formatter is constructed at boot
    # and ENV does not change under it, so this stays a hot-path-free check.
    def unredacted?
      return @unredacted if defined?(@unredacted)

      @unredacted = ENV.fetch("SPARC_LOG_CREDENTIALS", "false") == "true"
    end

    def redact(text)
      return text if unredacted?

      REDACTIONS.reduce(text) { |acc, (pattern, replacement)| acc.gsub(pattern, replacement) }
    end
  end
end
