# Review/approval state machine for trust-store documents (#630).
#
#   draft → pending_review → approved → (published, via Lifecycle)
#                         ↘ rejected → (back to draft on edit/resubmit)
#
# This is a THIRD axis, distinct from:
#   * the parse `status` enum (pending/processing/completed/failed), and
#   * `lifecycle_status` (started → in_progress → published).
#
# A document must be `approved` before it can be published when the
# SPARC_REQUIRE_DOCUMENT_APPROVAL gate is enabled (see Publishable). The
# transitions here are pure state mutation + provenance capture; authority
# checks, audit logging, and self-approval rules live in DocumentApprovalService
# so the API and UI share one code path (mirrors the back-matter promotion
# pattern, #372).
#
# NIST 800-53: CA-6 (Authorization), SA-10 (Developer Config Management).
module Approvable
  extend ActiveSupport::Concern

  APPROVAL_STATUSES = %w[draft pending_review approved rejected].freeze

  included do
    belongs_to :submitted_by_user, class_name: "User", optional: true
    belongs_to :approved_by_user, class_name: "User", optional: true

    validates :approval_status, inclusion: { in: APPROVAL_STATUSES }, allow_nil: true

    scope :pending_review, -> { where(approval_status: "pending_review") }
    scope :approved,       -> { where(approval_status: "approved") }
  end

  def approval_pending? = approval_status == "pending_review"
  def approved?         = approval_status == "approved"
  def approval_rejected? = approval_status == "rejected"

  # Draft for approval purposes = anywhere it can (re)enter review: a fresh
  # draft or a previously-rejected document the author has revised.
  def approval_draft? = approval_status.nil? || %w[draft rejected].include?(approval_status)

  # Only documents that can re-enter review may be submitted.
  def submittable_for_review? = approval_draft?

  # --- transitions (call via DocumentApprovalService, which authorizes + audits) ---

  def submit_for_review!(user)
    update!(approval_status: "pending_review", submitted_by_user: user, submitted_at: Time.current,
            rejection_reason: nil)
  end

  def mark_approved!(user)
    update!(approval_status: "approved", approved_by_user: user, approved_at: Time.current)
  end

  def mark_rejected!(reason)
    update!(approval_status: "rejected", rejection_reason: reason)
  end

  def approval_label
    case approval_status
    when "pending_review" then "Pending Review"
    when "approved"       then "Approved"
    when "rejected"       then "Rejected"
    else "Draft"
    end
  end

  def approval_badge_class
    case approval_status
    when "pending_review" then "badge-info"
    when "approved"       then "badge-ok"
    when "rejected"       then "badge-fail"
    else "badge-warn"
    end
  end
end
