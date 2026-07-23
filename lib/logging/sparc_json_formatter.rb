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
      case msg
      when String    then msg.strip
      when Exception then "#{msg.class}: #{msg.message}"
      when nil       then ""
      else msg.inspect
      end
    end
  end
end
