module ApplicationHelper
  # #902 — every flash key the app actually sets, mapped to the Bootstrap
  # contextual class that renders it.
  #
  # The layouts used to render `success`/`error`/`warning` only, but Rails'
  # own `redirect_to ..., notice:` / `alert:` shorthand writes `:notice` and
  # `:alert` — so 34 call sites across 12 controllers set a flash that was
  # never displayed. Among them was the evidence upload success notice, which
  # is why a *working* upload still looked like nothing happened (#902).
  #
  # Keep this the single source of truth: a key absent here renders nowhere,
  # silently, which is the bug this constant exists to prevent.
  FLASH_CLASSES = {
    "success" => "alert-success",
    "notice"  => "alert-success",
    "error"   => "alert-danger",
    "alert"   => "alert-danger",
    "warning" => "alert-warning"
  }.freeze

  # Displayable flash entries as [key, css_class, message] triples, in a stable
  # order (success before error before warning) so a request setting several
  # keys renders predictably. Blank messages are dropped — an empty flash
  # should not paint an empty box.
  def displayable_flashes
    FLASH_CLASSES.filter_map do |key, css_class|
      message = flash[key]
      next if message.blank?

      [ key, css_class, message ]
    end
  end

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
    "cdef_coverage"            => "cdef-coverage",
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

  # #897 — THE HOUSE RULE for rendering a stored value into an href.
  #
  # Escaping is the wrong tool here and it is worth being explicit about why,
  # because "Rails escapes it" is the reflex that let this sit. ERB escaping
  # protects the element BODY and blocks quote-breaking in an attribute; it does
  # nothing about the SCHEME. `<a href="<%= value %>">` with a stored
  # `javascript:alert(1)` renders a working XSS link, fully escaped.
  #
  # So: any stored value reaching a URL position goes through this. It returns
  # the value when the scheme is safe (or absent — a fragment or relative path
  # cannot execute) and nil when it is not, letting the view fall back to
  # rendering plain text rather than a live link.
  #
  # BackMatterResource validates this on write (#897), so this is the guard for
  # rows written BEFORE that validation existed — validation cannot retroactively
  # clean stored data.
  #
  # NIST 800-53: SI-10 (input validation), SC-18 (mobile code), SI-15 (output filtering).
  UNSAFE_URL_SCHEME_REGEX = /\A([a-zA-Z][a-zA-Z0-9+.\-]*):/
  SAFE_URL_SCHEMES = %w[http https mailto].freeze

  def safe_external_url(value)
    url = value.to_s.strip
    return nil if url.blank?

    match = UNSAFE_URL_SCHEME_REGEX.match(url)
    return url if match.nil? # fragment / relative — inert
    return url if SAFE_URL_SCHEMES.include?(match[1].downcase)

    nil
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

  # #1047 — a decorative colour delivered as a CLASS instead of an interpolated
  # `style=`, which does not survive removing `style-src 'unsafe-inline'`.
  #
  # KEYED ON THE HEX, not on the status. Keying it on the semantic variant would
  # have been tidier and would have changed what renders: `*_status_color` falls
  # back to COLOR_GRAY_DARK (#7f8c8d) for an unrecognised status, while
  # `*_status_variant` falls back to "neutral", which is COLOR_GRAY (#95a5a6).
  # Same input, different colour — a silent shade change on exactly the rows
  # whose data is unexpected. Taking the hex the existing helper already returned
  # makes the mapping exact by construction: the colour cannot drift, because it
  # is the same value, only delivered differently.
  #
  # An unmapped hex falls back to `slate`, which IS COLOR_GRAY_DARK, so an
  # unrecognised colour degrades to the same grey the helpers already use.
  ACCENT_TOKENS = {
    COLOR_GREEN     => "green",
    COLOR_BLUE      => "blue",
    COLOR_ORANGE    => "orange",
    COLOR_RED       => "red",
    COLOR_GRAY      => "gray",
    COLOR_GRAY_DARK => "slate",
    "#2ecc71"       => "emerald",
    "#9b59b6"       => "purple",
    "#8e44ad"       => "violet",
    "#bdc3c7"       => "silver",
    # POA&M risk_status uses two oranges the other status maps do not: without
    # these, accent_class falls back to slate and silently greys them.
    "#e67e22"       => "carrot",
    "#d35400"       => "pumpkin"
  }.freeze

  # `accent_class(ssp_status_color(status))` -> "sparc-accent--green".
  # Pair with .sparc-border-l-3 / -4 / .sparc-accent-text / .sparc-accent-bg,
  # which read `var(--sparc-accent)`.
  def accent_class(hex)
    "sparc-accent--#{ACCENT_TOKENS[hex] || 'slate'}"
  end

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
  # #1056 — render the image only if the FILE is actually there.
  #
  # `attached?` and `blob.persisted?` are both DB-level: the attachment row and
  # the blob row survive perfectly well after the underlying object is gone.
  # SPARC then emitted an <img> for a file that 404s, and because the avatar is
  # in the navbar that was a console error on EVERY authenticated page. It has
  # broken the smoke suite three times (130 failures / 521 x 404 most recently)
  # and reads as a catastrophic regression while meaning nothing.
  #
  # It is reachable in production, not just locally: storage migrated, a bucket
  # restored from a backup predating the upload, a lifecycle rule expiring an
  # object, or an operator deleting one.
  def safe_avatar_tag(user, **options)
    return content_tag(:span, user.initials) unless avatar_file_present?(user)

    begin
      image_tag user.avatar, **options
    rescue StandardError
      content_tag(:span, user.initials)
    end
  end

  # Existence is checked against the storage service, which costs a `stat` on
  # Disk but a HEAD REQUEST on S3 — and the navbar renders the avatar twice per
  # page. So the answer is memoized for the request and cached by blob key.
  #
  # Caching by key is safe in both directions: re-attaching creates a NEW blob
  # with a new key, so a cached "missing" can never outlive the upload that
  # fixes it.
  def avatar_file_present?(user)
    return false unless user.respond_to?(:avatar) && user.avatar.attached?

    blob = user.avatar.blob
    return false unless blob&.persisted? && blob.key.present?

    @avatar_file_present ||= {}
    return @avatar_file_present[blob.key] if @avatar_file_present.key?(blob.key)

    @avatar_file_present[blob.key] =
      Rails.cache.fetch("avatar_blob_present/#{blob.key}", expires_in: 5.minutes) do
        blob.service.exist?(blob.key)
      end
  rescue StandardError
    # A storage backend that cannot answer is not a reason to render a broken
    # image — fall back to initials, which always work.
    false
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

  # How many boundaries an organization shows before the rest fold away (#951).
  SIDEBAR_BOUNDARY_PAGE_SIZE = 10

  # Sidebar: Resources, split into the ones that stay top-level and the OSCAL
  # reference set that nests (#951).
  #
  # Grouped by HOST rather than by title. The shipped list happens to prefix six
  # entries with "OSCAL", but operators add their own through `SPARC_RESOURCES`
  # (#914), and a title-prefix rule would scatter those unpredictably — someone
  # else's "OSCAL Notes" would be swept into the nest while a NIST link titled
  # differently would not. The host is a fact about where the link goes.
  #
  # Nesting these is what stops nine external links pushing Help & Guides off
  # the bottom of the pane.
  OSCAL_REFERENCE_HOST = "pages.nist.gov"

  def sidebar_resource_groups
    resources = Array(SparcConfig.resources)
    nested, top_level = resources.partition do |resource|
      # The host must BE the reference host or a subdomain of it. A bare
      # `end_with?` is an incomplete check: "evilpages.nist.gov" ends with
      # "pages.nist.gov", so a lookalike host supplied through SPARC_RESOURCES
      # would be filed under the NIST group as though NIST published it.
      host = URI.parse(resource["href"].to_s).host.to_s.downcase
      host == OSCAL_REFERENCE_HOST || host.end_with?(".#{OSCAL_REFERENCE_HOST}")
    rescue URI::InvalidURIError
      false
    end
    { top_level: top_level, nested: nested }
  end

  # #1039 — one definition of "may this user change authoritative sources".
  # The controller guards with the same pair; a view that reimplemented the
  # check would be a second copy to keep in step, and the failure mode is a
  # button that renders and then 302s.
  def can_write_sources?
    return false unless current_user
    current_user.admin? || current_user.has_permission?("back_matter.write")
  end
end
