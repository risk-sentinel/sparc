# frozen_string_literal: true

# #860 — the one reading of "which IdP grants is SPARC currently refusing?"
#
# Shared by the admin queue (API and screen) and the daily digest email on
# purpose. Two implementations of this grouping would drift, and the failure
# would be quiet and embarrassing: an email reporting four affected users next
# to a screen reporting six, with no way to tell which is right.
#
# Reads audit events rather than a table of its own. An unmatched grant is not a
# task with a lifecycle — it is a current disagreement between the directory and
# the estate, and it heals by itself when someone creates the missing record,
# because every sign-in re-evaluates the grant.
class UnmatchedGrantQuery
  # Cap on how many events feed the grouping. A busy instance can record a great
  # many refusals, and the summary is a triage aid rather than a ledger; the
  # audit trail remains the complete record.
  GROUPING_LIMIT = 1000

  def initialize(window:, user_id: nil, include_dismissed: false)
    @window = window
    @user_id = user_id
    @include_dismissed = include_dismissed
  end

  # Always a RELATION, never an Array. Callers paginate it and call `.includes`
  # on it, and a method that silently returns an Array once some other table has
  # a row in it is the kind of bug that only appears in production.
  def events
    scope = AuditEvent.where(action: "idp_grant_skipped")
                      .where(created_at: @window.ago..)
                      .order(created_at: :desc)
    scope = scope.where(user_id: @user_id) if @user_id.present?
    return scope if @include_dismissed

    dismissed = DismissedIdpGrant.dismissed_grants
    return scope if dismissed.empty?

    scope.where.not(CANONICAL_GRANT_SQL + " IN (?)", dismissed.to_a)
  end

  # Mirrors IdpGrant.canonicalize (strip, then downcase) in SQL, because the
  # grant lives in a jsonb key and filtering it in Ruby would turn this into an
  # Array. The duplication is deliberate and guarded: a spec asserts this
  # expression and IdpGrant.canonicalize agree on the awkward inputs, so the day
  # one changes without the other, that spec fails rather than a dismissed grant
  # quietly reappearing.
  CANONICAL_GRANT_SQL = "LOWER(BTRIM(audit_events.metadata->>'grant'))"

  # [{ reason:, occurrences:, affected_users:, example_grant: }], worst first.
  #
  # `affected_users` counts DISTINCT users, and that distinction matters: one
  # person signing in five times is five events and ONE problem. Ranking by
  # occurrences would put a single persistent user above a misconfiguration
  # locking out a whole team.
  def summary
    events.limit(GROUPING_LIMIT).group_by { |e| e.metadata["reason"] }.map do |reason, group|
      {
        reason: reason,
        occurrences: group.size,
        affected_users: group.map(&:user_id).compact.uniq.size,
        example_grant: group.first.metadata["grant"]
      }
    end.sort_by { |row| -row[:affected_users] }
  end

  def any? = events.exists?
end
