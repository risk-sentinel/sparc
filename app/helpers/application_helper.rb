module ApplicationHelper
  SSP_STATUS_COLORS = {
    # Current schema values
    "Implemented"              => "#27ae60",
    "Deferred"                 => "#3498db",
    "Not Applicable"           => "#95a5a6",
    "Will Not Implement"       => "#e74c3c",
    # Legacy values kept for backward compatibility with existing data
    "Partially Implemented"    => "#f39c12",
    "Planned"                  => "#3498db",
    "Alternative Implementation" => "#9b59b6",
    "Not Implemented"          => "#e74c3c"
  }.freeze

  TPR_STATUS_COLORS = {
    # Result field values
    "Passed"                => "#27ae60",
    "Pass"                  => "#27ae60",
    "Failed"                => "#e74c3c",
    # Working Status values
    "Final Satisfied"       => "#27ae60",
    "Final - Not Satisfied" => "#e74c3c",
    "Not Satisfied"         => "#f39c12",
    "Not Specified"         => "#95a5a6",
    # Legacy values
    "Partial"               => "#f39c12",
    "Fail"                  => "#e74c3c",
    "Not Tested"            => "#95a5a6",
    "Not Applicable"        => "#bdc3c7"
  }.freeze

  def ssp_status_color(status, _count = 0)
    SSP_STATUS_COLORS[status] || "#7f8c8d"
  end

  def tpr_status_color(status, _count = 0)
    TPR_STATUS_COLORS[status] || "#7f8c8d"
  end

  PROFILE_SEVERITY_COLORS = {
    "high"   => "#e74c3c",
    "medium" => "#f39c12",
    "low"    => "#3498db",
    "info"   => "#95a5a6"
  }.freeze

  def profile_severity_color(severity)
    PROFILE_SEVERITY_COLORS[severity.to_s.downcase] || "#7f8c8d"
  end
end
