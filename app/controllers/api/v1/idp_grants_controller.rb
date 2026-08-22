# frozen_string_literal: true

# #860 — the unmatched-grant queue.
#
#   GET /api/v1/idp_grants/unmatched
#
# What an administrator needs when a claim names something SPARC does not have.
# The epic's hard constraint is that a grant naming an unknown organization,
# boundary or role is **recorded and surfaced, never created** — auto-creating
# would let the IdP mint tenants. Recording it without surfacing it is only half
# of that, and the half nobody notices: the user signs in with less access than
# their directory says they should have, and the only trace is a log line.
#
# ── Why this reads the audit trail instead of its own table ───────────────
#
# An unmatched grant is not a task with a lifecycle; it is a CURRENT DISAGREEMENT
# between the directory and the estate, and it heals by itself. Create the
# missing boundary and the user's next login resolves the grant with no further
# action. A dedicated table would therefore need reconciling against reality on
# every sync, and a stale row in it would be indistinguishable from a real one.
#
# Audit events already record every skipped grant with its reason, and they are
# immutable, which is what an assessor wants. So the queue is a read model over
# them: "these grants were refused recently, and this is why."
#
# NIST 800-53 Controls:
#   AC-2 Account Management, AU-6 Audit Review, AU-12 Audit Record Generation
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::IdpGrantsController < Api::V1::BaseController
  before_action :authorize_admin!

  DEFAULT_WINDOW_DAYS = 30
  MAX_WINDOW_DAYS = 365

  # GET /api/v1/idp_grants/unmatched
  #
  # Params:
  #   days  — how far back to look (default 30, max 365)
  #   user_id — narrow to one user
  def unmatched
    query = UnmatchedGrantQuery.new(window: window, user_id: params[:user_id])
    result = paginate(query.events.includes(:user), items: 50)

    render json: {
      data: result[:data].map { |event| serialize(event) },
      meta: result[:meta].merge(
        window_days: window_days,
        # Grouped so an administrator sees "this boundary is missing and it is
        # costing four people access", not four separate incidents.
        summary: query.summary
      )
    }
  end

  private

  def window_days
    requested = params[:days].presence&.to_i || DEFAULT_WINDOW_DAYS
    requested.clamp(1, MAX_WINDOW_DAYS)
  end

  def window = window_days.days

  def serialize(event)
    {
      id: event.id,
      occurred_at: event.created_at.iso8601,
      user: event.user && { id: event.user.id, email: event.user.email },
      grant: event.metadata["grant"],
      reason: event.metadata["reason"],
      # Present when the grant PARSED and resolved but was refused on conflict,
      # rather than failing to resolve at all.
      role: event.metadata["role"],
      organization: event.metadata["organization"],
      authorization_boundary: event.metadata["authorization_boundary"]
    }.compact
  end
end
