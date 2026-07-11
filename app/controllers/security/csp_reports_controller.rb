# frozen_string_literal: true

module Security
  # Receives Content-Security-Policy violation reports (#528, epic #650).
  #
  # The CSP header carries `report-uri /security/csp-violations`; when a
  # directive is violated the browser POSTs a JSON report here. We log a
  # structured line (CloudWatch-ingestible, same pattern as AuditEvent /
  # rack-attack) so CSP violations become self-surfacing telemetry instead
  # of dying silently in each user's console.
  #
  # Deliberately NOT persisted to the AuditEvent table: reports are
  # high-volume, unauthenticated, and carry attacker-influenceable content
  # (blocked-uri, source-file). Flooding the compliance audit trail (AU-9,
  # immutable) with that is a liability. A dedicated DB-backed model is
  # tracked as an option in #528; structured logs are the source of truth.
  #
  # Inherits ActionController::Base directly (not ApplicationController) so
  # the endpoint carries no auth gate, session timeout, CSRF token, or
  # modern-browser guard — none apply to a machine-posted report beacon.
  #
  # Rate-limited per-IP by Rack::Attack ("csp-reports/min/ip", #513).
  #
  # NIST 800-53: SI-4 (Information System Monitoring), SC-18 (Mobile Code).
  # rubydre:S7905 ("inherit from ApplicationController") is a false positive here:
  # inheriting ActionController::Base directly is deliberate — see the class
  # comment above (write-only unauthenticated CSP beacon; no auth/session/CSRF/
  # browser guard applies; skip_forgery_protection; Rack::Attack rate-limited;
  # 8 KB read cap). Suppressed inline.
  class CspReportsController < ActionController::Base # NOSONAR(rubydre:S7905)
    # Browsers post reports with no CSRF token; this is a write-only beacon.
    skip_forgery_protection

    # Cap on how much of the report body we read/parse. Reports are small;
    # anything larger is noise or an attempt to flood the logs.
    MAX_REPORT_BYTES = 8_192

    def create
      body = request.body.read(MAX_REPORT_BYTES).to_s
      report = parse_report(body)

      if report
        Rails.logger.warn(
          { csp_violation: {
            violated_directive: report["violated-directive"] || report["effective-directive"],
            blocked_uri: report["blocked-uri"],
            document_uri: report["document-uri"],
            source_file: report["source-file"],
            line_number: report["line-number"],
            disposition: report["disposition"],
            ip: request.remote_ip
          } }.to_json
        )
      else
        Rails.logger.warn("[csp-violation] unparseable report from ip=#{request.remote_ip}")
      end

      # Always 204 — a report beacon must never surface an error to the page.
      head :no_content
    end

    private

    # Accepts both the legacy report-uri envelope ({"csp-report": {...}})
    # and a bare report object. Returns the inner hash or nil.
    def parse_report(body)
      return nil if body.blank?

      parsed = JSON.parse(body)
      return nil unless parsed.is_a?(Hash)

      parsed["csp-report"].is_a?(Hash) ? parsed["csp-report"] : parsed
    rescue JSON::ParserError
      nil
    end
  end
end
