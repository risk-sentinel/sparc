# frozen_string_literal: true

# View helpers for the #447/#809/#811 HDF Amendment triage board — mapping a
# finding's re-occurrence lifecycle and a disposition's approval state to Bootstrap
# contextual colours.
module HdfTriageHelper
  LIFECYCLE_BADGE = {
    "new"             => "primary",
    "carried_forward" => "secondary",
    "re_failed"       => "danger",
    "expired"         => "warning text-dark",
    "superseded"      => "light text-dark"
  }.freeze

  APPROVAL_BADGE = {
    "draft"    => "secondary",
    "approved" => "success",
    "rejected" => "dark"
  }.freeze

  def lifecycle_badge_class(status)
    LIFECYCLE_BADGE.fetch(status.to_s, "secondary")
  end

  def approval_badge_class(status)
    APPROVAL_BADGE.fetch(status.to_s, "secondary")
  end
end
