# frozen_string_literal: true

# v1.17.2 — how a POA&M entry is RESOLVED, as distinct from deleted.
#
# Delete is for an entry that should never have existed. A risk that was dealt
# with is closed, and the POA&M keeps it: NIST SP 800-53 Rev 5 CA-5 has the plan
# document "the planned remediation actions" and be updated from findings, and
# PM-4a.2 has it "document the remedial ... actions to adequately respond to
# risk". Deleting a resolved risk erases exactly that record.
#
# OSCAL carries resolution in two places, and only two:
#
#   * a risk's `status` (`closed`; the other values stay on the edit form), with
#     the change recorded in its `risk-log` as an entry whose `status-change`
#     names the new status, and when, and why;
#   * a remediation's `lifecycle` (`completed`).
#
# Observations, findings, POA&M items and components have no status in OSCAL;
# they resolve through the risk they point at.
#
# The note is REQUIRED (owner, 2026-10-22). A closure with no reason claims a
# resolution without recording it; RA-7 asks for a justification when a risk is
# accepted rather than mitigated. It is what the risk-log entry's description
# carries into the export.
#
# One definition for the web actions and Api::V1, so the two cannot disagree on
# what closing means.
#
# NIST 800-53: CA-5, PM-4, RA-7.
class PoamResolutionService
  class Refused < StandardError; end

  CLOSED = "closed"
  REOPENED = "open"

  def self.close!(risk, note:)
    raise Refused, "This risk is already closed." if risk.status == CLOSED

    change_status!(risk, CLOSED, "Closed", note)
  end

  def self.reopen!(risk, note:)
    raise Refused, "Only a closed risk can be reopened." unless risk.status == CLOSED

    change_status!(risk, REOPENED, "Reopened", note)
  end

  def self.complete!(remediation)
    raise Refused, "This remediation is already completed." if remediation.lifecycle == "completed"

    remediation.update!(lifecycle: "completed")
    remediation
  end

  def self.change_status!(risk, status, title, note)
    raise Refused, "Say why: a note is required to change a risk's status here." if note.to_s.strip.empty?

    log = (risk.risk_log_data.presence || {}).deep_dup
    log["entries"] = Array(log["entries"]) + [ {
      "uuid" => SecureRandom.uuid,
      "title" => title,
      "description" => note.to_s.strip,
      "start" => Time.current.utc.iso8601,
      "status-change" => status
    } ]

    risk.update!(status: status, risk_log_data: log)
    risk
  end
  private_class_method :change_status!
end
