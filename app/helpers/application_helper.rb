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

  SAR_STATUS_COLORS = {
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

  def sar_status_color(status, _count = 0)
    SAR_STATUS_COLORS[status] || "#7f8c8d"
  end

  # Semantic variant keys for .sparc-status--<variant> (WORM, #599 Round 2).
  # The *_color maps above stay for decorative fills (heatmap bars, legends);
  # these drive AA-correct badge text. Same domain space, no hex.
  SSP_STATUS_VARIANTS = {
    "Implemented"                => "success",
    "Deferred"                   => "info",
    "Not Applicable"             => "neutral",
    "Will Not Implement"         => "danger",
    "Partially Implemented"      => "warning",
    "Planned"                    => "info",
    "Alternative Implementation" => "purple",
    "Not Implemented"            => "danger"
  }.freeze

  SAR_STATUS_VARIANTS = {
    "Passed"                => "success",
    "Pass"                  => "success",
    "Failed"                => "danger",
    "Final Satisfied"       => "success",
    "Final - Not Satisfied" => "danger",
    "Not Satisfied"         => "warning",
    "Not Specified"         => "neutral",
    "Partial"               => "warning",
    "Fail"                  => "danger",
    "Not Tested"            => "neutral",
    "Not Applicable"        => "neutral"
  }.freeze

  def ssp_status_variant(status, _count = 0)
    SSP_STATUS_VARIANTS[status] || "neutral"
  end

  def sar_status_variant(status, _count = 0)
    SAR_STATUS_VARIANTS[status] || "neutral"
  end

  CDEF_SEVERITY_COLORS = {
    "high"   => "#e74c3c",
    "medium" => "#f39c12",
    "low"    => "#3498db",
    "info"   => "#95a5a6"
  }.freeze

  def cdef_severity_color(severity)
    CDEF_SEVERITY_COLORS[severity.to_s.downcase] || "#7f8c8d"
  end

  CDEF_SEVERITY_VARIANTS = {
    "high"   => "danger",
    "medium" => "warning",
    "low"    => "info",
    "info"   => "neutral"
  }.freeze

  def cdef_severity_variant(severity)
    CDEF_SEVERITY_VARIANTS[severity.to_s.downcase] || "neutral"
  end

  SAP_METHOD_COLORS = {
    "examine"   => "#3498db",
    "interview" => "#f39c12",
    "test"      => "#e74c3c",
    "multiple"  => "#9b59b6",
    "(None)"    => "#95a5a6"
  }.freeze

  def sap_method_color(method)
    m = method.to_s
    return SAP_METHOD_COLORS["multiple"] if m.include?(",")
    SAP_METHOD_COLORS[m] || "#7f8c8d"
  end

  SAP_METHOD_VARIANTS = {
    "examine"   => "info",
    "interview" => "warning",
    "test"      => "danger",
    "multiple"  => "purple",
    "(None)"    => "neutral"
  }.freeze

  def sap_method_variant(method)
    m = method.to_s
    return "purple" if m.include?(",")
    SAP_METHOD_VARIANTS[m] || "neutral"
  end

  # Objective rollup colors -- used by both SAP and SAR show pages for the
  # secondary "Status by Control Family" heatmap. Mirrors the per-row pill
  # colors in _objectives_table partials so legend and cells match.
  SAP_OBJECTIVE_STATUS_COLORS = {
    "failed"         => "#e74c3c",
    "in-progress"    => "#f39c12",
    "pending"        => "#95a5a6",
    "passing"        => "#27ae60",
    "not_applicable" => "#7f8c8d",
    "not_assessed"   => "#bdc3c7"
  }.freeze

  def sap_objective_status_color(status)
    SAP_OBJECTIVE_STATUS_COLORS[status.to_s] || "#7f8c8d"
  end
  alias_method :sar_objective_status_color, :sap_objective_status_color

  SAP_OBJECTIVE_STATUS_VARIANTS = {
    "failed"         => "danger",
    "in-progress"    => "warning",
    "pending"        => "neutral",
    "passing"        => "success",
    "not_applicable" => "neutral",
    "not_assessed"   => "neutral"
  }.freeze

  def sap_objective_status_variant(status)
    SAP_OBJECTIVE_STATUS_VARIANTS[status.to_s] || "neutral"
  end
  alias_method :sar_objective_status_variant, :sap_objective_status_variant

  PROFILE_PRIORITY_COLORS = {
    "P1"     => "#e74c3c",
    "P2"     => "#f39c12",
    "P3"     => "#3498db",
    "(None)" => "#95a5a6"
  }.freeze

  def profile_priority_color(priority)
    PROFILE_PRIORITY_COLORS[priority.to_s] || "#7f8c8d"
  end

  PROFILE_PRIORITY_VARIANTS = {
    "P1"     => "danger",
    "P2"     => "warning",
    "P3"     => "info",
    "(None)" => "neutral"
  }.freeze

  def profile_priority_variant(priority)
    PROFILE_PRIORITY_VARIANTS[priority.to_s] || "neutral"
  end

  AB_STATUS_COLORS = {
    "draft"         => "#95a5a6",
    "active"        => "#3498db",
    "authorized"    => "#27ae60",
    "deauthorized"  => "#e74c3c"
  }.freeze

  # Returns the authorization boundaries to display in the navbar.
  # Admins see all boundaries; regular users see only their assigned ones.
  def nav_authorization_boundaries
    return [] unless defined?(current_user) && current_user

    if current_user.admin?
      AuthorizationBoundary.order(:name).limit(10)
    else
      current_user.authorization_boundaries.order(:name).limit(10)
    end
  end

  def ab_status_color(status)
    AB_STATUS_COLORS[status.to_s] || "#7f8c8d"
  end

  AB_STATUS_VARIANTS = {
    "draft"        => "neutral",
    "active"       => "info",
    "authorized"   => "success",
    "deauthorized" => "danger"
  }.freeze

  def ab_status_variant(status)
    AB_STATUS_VARIANTS[status.to_s] || "neutral"
  end

  # Safe avatar image tag — falls back to initials if blob is missing from storage
  def safe_avatar_tag(user, **options)
    if user.avatar.attached? && user.avatar.blob&.persisted?
      begin
        image_tag user.avatar, **options
      rescue StandardError
        content_tag(:span, user.initials)
      end
    else
      content_tag(:span, user.initials)
    end
  end

  # Sidebar: organizations with authorization boundaries for current user
  def sidebar_organizations
    return [] unless defined?(current_user) && current_user

    orgs = if current_user.admin?
      Organization.where(status: :active).includes(:authorization_boundaries).order(:name)
    else
      current_user.organizations.where(status: :active).includes(:authorization_boundaries).order(:name)
    end
    orgs || []
  end
end
