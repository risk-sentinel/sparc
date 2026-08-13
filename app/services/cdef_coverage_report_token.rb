# frozen_string_literal: true

# #904 — carry an analysed report from the report screen to the save action
# without re-uploading, and without trusting the browser.
#
# The upload is discarded during analysis, so saving would otherwise mean asking
# the operator to select the same files again. The DERIVED report, though, is
# exactly the data this feature was designed to be safe to hold: service keys,
# resource type names, counts, verdicts. Nothing in it came from a resource's
# attributes.
#
# So it round-trips through the client — signed, because a saved coverage run is
# a compliance artifact and an unsigned payload would let a caller assert
# whatever they liked about their own coverage. Same shape as the
# bulk_apply_converter preview/confirm pair (#499 slice 3/4).
#
# Signed, not encrypted: the contents are already safe for the operator to see —
# they are looking at them on the screen. What must not be possible is ALTERING
# them undetected.
class CdefCoverageReportToken
  Error = Class.new(StandardError)

  PURPOSE = "cdef_coverage_report"
  EXPIRY = 1.hour

  def self.sign(report_hash)
    verifier.generate(report_hash.as_json, purpose: PURPOSE, expires_in: EXPIRY)
  end

  # Returns the report hash, or raises Error for a tampered, foreign, or expired
  # token. Expiry is short on purpose: this exists to bridge two requests in one
  # sitting, not to be a durable handle on an analysis.
  def self.verify(token)
    raise Error, "Missing analysis token" if token.blank?

    verifier.verified(token.to_s, purpose: PURPOSE) ||
      raise(Error, "This analysis is no longer valid. Re-run it and save again.")
  end

  def self.verifier = Rails.application.message_verifier(PURPOSE)
end
