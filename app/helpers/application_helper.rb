module ApplicationHelper
  # #784 — per-screen contextual help. Maps a controller (controller_path, so
  # namespaced admin controllers work) to the slug of the User Guide that best
  # covers it. Keys must stay in sync with wiki/User-Guide-*.md filenames; the
  # "?" nav link falls back to the Help Center index when a screen isn't mapped.
  CONTEXTUAL_GUIDE = {
    "home"                     => "getting-oriented",
    "ssp_documents"            => "system-security-plans",
    "sar_documents"            => "assessment-results",
    "sap_documents"            => "assessment-plans",
    "poam_documents"           => "poam",
    "cdef_documents"           => "component-definitions",
    "profile_documents"        => "control-catalogs-and-baselines",
    "control_catalogs"         => "control-catalogs-and-baselines",
    "control_mappings"         => "control-catalogs-and-baselines",
    "converters"               => "converters-and-imports",
    "authorization_boundaries" => "authorization-boundaries",
    "hdf_triage"               => "hdf-amendment-triage",
    "evidences"                => "evidence-and-attestations",
    "authoritative_sources"    => "trust-store",
    "promotion_queue"          => "trust-store",
    "webauthn_credentials"     => "security-keys",
    "admin/users"              => "administration",
    "admin/roles"              => "administration",
    "admin/service_accounts"   => "administration",
    "admin/organizations"      => "administration"
  }.freeze

  # Slug of the guide most relevant to the current screen, or nil.
  def contextual_help_slug
    CONTEXTUAL_GUIDE[controller_path] || CONTEXTUAL_GUIDE[controller_name]
  end

  # Deep-link to the contextual guide, falling back to the Help Center index.
  def contextual_help_path
    slug = contextual_help_slug
    slug ? help_guide_path(slug) : help_path
  end

  # #796 — every User Guide, for the sidebar "Help & Guides" menu (sorted by
  # title). Memoized per request; the sidebar renders once per page.
  def sidebar_help_guides
    @sidebar_help_guides ||= UserGuideLibrary.all
  end

  # #870 — a small "?" beside a field label, answering the micro-question
  # ("what goes in here?") without sending the operator to a full guide.
  #
  #   <%= f.label :source, class: "form-label" %><%= field_help "Where the
  #       artefact came from — the scanner, system or person that produced it." %>
  #
  # A <button>, not a <span>: it must be reachable by keyboard, and Bootstrap's
  # default tooltip trigger is "hover focus", so tabbing to it shows the text.
  # Help that only appears on hover is invisible to keyboard and touch users.
  #
  # No inline handlers — CSP has no 'unsafe-inline', so the tooltip is wired up
  # by data attributes and initialised on turbo:load in application.js.
  def field_help(text, placement: "top")
    return if text.blank?

    tag.button(
      "?",
      type: "button",
      class: "sparc-field-help",
      tabindex: 0,
      data: { bs_toggle: "tooltip", bs_placement: placement, bs_title: text },
      aria: { label: "Help: #{text}" }
    )
  end

  # #808 — true when the gateway forwarded a verified client cert on THIS
  # request (login page). Same header + success check piv_sessions#create uses,
  # so "button shown" ⟺ "the gateway would accept the cert". The cert is
  # presented at the TLS handshake, so this reflects page-load connection state.
  def piv_certificate_present?
    request.headers[SparcConfig.piv_verify_header].to_s.strip
           .casecmp?(SparcConfig.piv_verify_success)
  end

  # #808 — whether to render the PIV/CAC login button. Always shown when PIV is
  # enabled, unless SPARC_PIV_LOGIN_REQUIRES_CERT gates it on a present cert.
  def show_piv_login_button?
    return false unless SparcConfig.enable_piv?

    piv_certificate_present? || !SparcConfig.piv_login_requires_cert?
  end

  # Status-color palette (hue-named; the same swatch is reused across the
  # *_STATUS_COLORS / *_SEVERITY_COLORS maps below).
  COLOR_GREEN     = "#27ae60".freeze  # success / implemented / passed
  COLOR_BLUE      = "#3498db".freeze  # info / planned / deferred
  COLOR_ORANGE    = "#f39c12".freeze  # partial / in-progress
  COLOR_RED       = "#e74c3c".freeze  # failure / not-implemented
  COLOR_GRAY      = "#95a5a6".freeze  # not-applicable / none
  COLOR_GRAY_DARK = "#7f8c8d".freeze  # default fallback

  LABEL_NONE           = "(None)".freeze
  LABEL_NOT_APPLICABLE = "Not Applicable".freeze

  SSP_STATUS_COLORS = {
    # Current schema values
    "Implemented"              => COLOR_GREEN,
    "Deferred"                 => COLOR_BLUE,
    LABEL_NOT_APPLICABLE           => COLOR_GRAY,
    "Will Not Implement"       => COLOR_RED,
    # Legacy values kept for backward compatibility with existing data
    "Partially Implemented"    => COLOR_ORANGE,
    "Planned"                  => COLOR_BLUE,
    "Alternative Implementation" => "#9b59b6",
    "Not Implemented"          => COLOR_RED
  }.freeze

  SAR_STATUS_COLORS = {
    # Result field values
    "Passed"                => COLOR_GREEN,
    "Pass"                  => COLOR_GREEN,
    "Failed"                => COLOR_RED,
    # Working Status values
    "Final Satisfied"       => COLOR_GREEN,
    "Final - Not Satisfied" => COLOR_RED,
    "Not Satisfied"         => COLOR_ORANGE,
    "Not Specified"         => COLOR_GRAY,
    # Legacy values
    "Partial"               => COLOR_ORANGE,
    "Fail"                  => COLOR_RED,
    "Not Tested"            => COLOR_GRAY,
    LABEL_NOT_APPLICABLE        => "#bdc3c7"
  }.freeze

  def ssp_status_color(status, _count = 0)
    SSP_STATUS_COLORS[status] || COLOR_GRAY_DARK
  end

  def sar_status_color(status, _count = 0)
    SAR_STATUS_COLORS[status] || COLOR_GRAY_DARK
  end

  # Semantic variant keys for .sparc-status--<variant> (WORM, #599 Round 2).
  # The *_color maps above stay for decorative fills (heatmap bars, legends);
  # these drive AA-correct badge text. Same domain space, no hex.
  SSP_STATUS_VARIANTS = {
    "Implemented"                => "success",
    "Deferred"                   => "info",
    LABEL_NOT_APPLICABLE             => "neutral",
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
    LABEL_NOT_APPLICABLE        => "neutral"
  }.freeze

  def ssp_status_variant(status, _count = 0)
    SSP_STATUS_VARIANTS[status] || "neutral"
  end

  def sar_status_variant(status, _count = 0)
    SAR_STATUS_VARIANTS[status] || "neutral"
  end

  CDEF_SEVERITY_COLORS = {
    "high"   => COLOR_RED,
    "medium" => COLOR_ORANGE,
    "low"    => COLOR_BLUE,
    "info"   => COLOR_GRAY
  }.freeze

  def cdef_severity_color(severity)
    CDEF_SEVERITY_COLORS[severity.to_s.downcase] || COLOR_GRAY_DARK
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
    "examine"   => COLOR_BLUE,
    "interview" => COLOR_ORANGE,
    "test"      => COLOR_RED,
    "multiple"  => "#9b59b6",
    LABEL_NONE    => COLOR_GRAY
  }.freeze

  def sap_method_color(method)
    m = method.to_s
    return SAP_METHOD_COLORS["multiple"] if m.include?(",")
    SAP_METHOD_COLORS[m] || COLOR_GRAY_DARK
  end

  SAP_METHOD_VARIANTS = {
    "examine"   => "info",
    "interview" => "warning",
    "test"      => "danger",
    "multiple"  => "purple",
    LABEL_NONE    => "neutral"
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
    "failed"         => COLOR_RED,
    "in-progress"    => COLOR_ORANGE,
    "pending"        => COLOR_GRAY,
    "passing"        => COLOR_GREEN,
    "not_applicable" => COLOR_GRAY_DARK,
    "not_assessed"   => "#bdc3c7"
  }.freeze

  def sap_objective_status_color(status)
    SAP_OBJECTIVE_STATUS_COLORS[status.to_s] || COLOR_GRAY_DARK
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
    "P1"     => COLOR_RED,
    "P2"     => COLOR_ORANGE,
    "P3"     => COLOR_BLUE,
    LABEL_NONE => COLOR_GRAY
  }.freeze

  def profile_priority_color(priority)
    PROFILE_PRIORITY_COLORS[priority.to_s] || COLOR_GRAY_DARK
  end

  PROFILE_PRIORITY_VARIANTS = {
    "P1"     => "danger",
    "P2"     => "warning",
    "P3"     => "info",
    LABEL_NONE => "neutral"
  }.freeze

  def profile_priority_variant(priority)
    PROFILE_PRIORITY_VARIANTS[priority.to_s] || "neutral"
  end

  AB_STATUS_COLORS = {
    "draft"         => COLOR_GRAY,
    "active"        => COLOR_BLUE,
    "authorized"    => COLOR_GREEN,
    "deauthorized"  => COLOR_RED
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
    AB_STATUS_COLORS[status.to_s] || COLOR_GRAY_DARK
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
