# frozen_string_literal: true

# #630 / 1.18.0-rf #1295 — the documents waiting for a reviewer, as ONE
# definition read by the review queue screen and by the header's review-queue
# indicator, so the count in the header is always the length of the list it
# opens.
#
# Approval authority is decided per document by DocumentApprovalService (the
# same code path as the per-type approve actions and the API), so the list is an
# Array, not a relation.
#
# NIST SP 800-53 Rev 5: AC-3, AC-6 (only an approver is offered the queue).
module ReviewQueue
  REVIEWABLE_TYPES = [ ControlCatalog, ProfileDocument, CdefDocument ].freeze

  extend self

  # The pending documents this user may approve.
  def approvable_for(user)
    return [] unless user

    REVIEWABLE_TYPES.flat_map do |klass|
      klass.pending_review.to_a.select do |doc|
        DocumentApprovalService.new(document: doc, actor: user).can_approve?
      end
    end
  end

  # May this user approve any reviewable type at all? Mirrors
  # DocumentApprovalService#can_approve?: an instance administrator, a policy
  # manager, or the per-type approve key (cdef.approve on any boundary counts,
  # as CdefWriteAccess grants it there).
  def approver?(user)
    return false unless user
    return true if user.instance_administrator? || user.has_role?("policy_manager")

    DocumentApprovalService::APPROVE_PERMISSION.values.any? { |key| user.has_any_permission?(key) }
  end
end
