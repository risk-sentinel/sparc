# frozen_string_literal: true

# #860 — daily digest of IdP grants SPARC could not honour.
#
# An unmatched grant is silent by nature: the sign-in succeeds, the user simply
# has less access than their directory says, and nothing about the login looks
# wrong. Without a push, the first signal an administrator gets is a support
# ticket. This is the push.
#
# A DIGEST rather than an alert per event, deliberately. One missing boundary
# produces one refusal per affected user per sign-in, so per-event mail would
# send dozens of messages describing a single thing to create — and mail that
# arrives in bulk gets filtered, which is how a real signal stops being one.
#
# NIST 800-53: AC-2(1) Automated Account Management, AU-6 Audit Review.
class UnmatchedGrantDigestJob < ApplicationJob
  queue_as :background

  WINDOW_HOURS = 24

  def perform
    # Not an error: an instance with no mail configured is a supported
    # deployment, and the queue is still there to read.
    return unless SparcConfig.enable_smtp?

    query = UnmatchedGrantQuery.new(window: WINDOW_HOURS.hours)
    summary = query.summary
    return if summary.empty?

    IdpGrantMailer.unmatched_grants_digest(summary: summary, window_hours: WINDOW_HOURS)
                  .deliver_later

    Rails.logger.info(
      "[UnmatchedGrantDigest] #{summary.size} distinct #{'reason'.pluralize(summary.size)}, " \
      "#{summary.sum { |r| r[:affected_users] }} affected users"
    )
  end
end
