# frozen_string_literal: true

# #630 — Review queue for trust-store documents (Catalog, Profile, CDEF).
# Lists every document currently `pending_review` that the signed-in user is
# authorized to approve, with inline approve/reject (which post to the existing
# per-type approval routes). For profiles, a baseline-review summary (#633) is
# computed so the reviewer can sign off on control selection + ODP values.
#
# Approve/reject authority is enforced by DocumentApprovalService (same code
# path as the per-type actions and the API).
class ReviewQueueController < ApplicationController
  REVIEWABLE_TYPES = [ ControlCatalog, ProfileDocument, CdefDocument ].freeze

  def index
    @pending = REVIEWABLE_TYPES.flat_map do |klass|
      klass.pending_review.to_a.select do |doc|
        DocumentApprovalService.new(document: doc, actor: current_user).can_approve?
      end
    end

    # #633 — baseline diff for any pending profiles, keyed by record.
    @baseline_reviews = @pending.grep(ProfileDocument).index_with do |profile|
      BaselineReviewService.new(profile).review
    end
  end
end
