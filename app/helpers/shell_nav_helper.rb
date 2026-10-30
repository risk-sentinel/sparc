# frozen_string_literal: true

# 1.18.0-rf — the organization layout's navigation (owner, 2026-10-29), behind
# SPARC_NAV_SHELL. Two tab bars under the header:
#
#   organization  Overview, Boundaries, the document types by layer, and the
#                 admin screens (People, Settings)
#   boundary      inside one boundary — its page, or a list filtered to it —
#                 the same document types narrowed to that boundary
#
# Each tab is shown exactly when today's menus show its entry (the predicates
# in shared/_main_nav: signed in or sign-in disabled, controls_publicly_
# accessible?, admin_access?, instance_administrator?), so the tabs never
# offer a page that would refuse the viewer.
#
# Counts come from BoundaryNavCounts (the lists' own relations), so a count
# never promises a record its list will not show.
#
# NIST SP 800-53 Rev 5:
#   AC-3 Access Enforcement — tabs and counts follow what the viewer may open.
module ShellNavHelper
  Tab = Struct.new(:key, :label, :path, :icon, :layer, :count, keyword_init: true)
  SEPARATOR = :separator

  # Which tab a controller belongs to.
  ORG_TAB_FOR = {
    "home" => :overview, "authorization_boundaries" => :boundaries, "profile_documents" => :baselines,
    "ssp_documents" => :ssp, "cdef_documents" => :cdef, "sap_documents" => :sap, "sar_documents" => :sar,
    "evidences" => :evidence, "poam_documents" => :poam, "admin/users" => :people,
    "admin/organizations" => :settings
  }.freeze
  BOUNDARY_TAB_FOR = ORG_TAB_FOR.merge("authorization_boundaries" => :overview,
                                       "leveraged_poam_documents" => :leveraged).freeze

  def shell_nav?
    SparcConfig.nav_shell? && (!SparcConfig.any_auth_enabled? || signed_in?)
  end

  # The boundary the page is inside is ShellContext#shell_boundary (a helper
  # method), shared with the switcher's recently-used list.

  # The viewer's organization when they belong to exactly one; the switcher
  # between organizations is #1291.
  def shell_org_name
    return @shell_org_name if defined?(@shell_org_name)

    orgs = current_user ? current_user.organizations.order(:name).limit(2).to_a : []
    @shell_org_name = orgs.one? ? orgs.first.name : "All organizations"
  end

  def shell_current_tab(boundary)
    (boundary ? BOUNDARY_TAB_FOR : ORG_TAB_FOR)[controller_path]
  end

  def shell_org_tabs
    counts = shell_nav_counts(nil)
    reference = controls_publicly_accessible?
    [
      Tab.new(key: :overview, label: "Overview", path: root_path, icon: "house"),
      Tab.new(key: :boundaries, label: "Boundaries", path: authorization_boundaries_path, icon: "shield",
              layer: :enterprise, count: AuthorizationBoundary.visible_to(current_user).count),
      SEPARATOR,
      (Tab.new(key: :baselines, label: "Baselines", path: profile_documents_path, icon: "list-checks",
               layer: :controls, count: ProfileDocument.count) if reference),
      Tab.new(key: :ssp, label: "SSPs", path: ssp_documents_path, icon: "file-text",
              layer: :implementation, count: counts[:ssp]),
      (Tab.new(key: :cdef, label: "CDEFs", path: cdef_documents_path, icon: "puzzle",
               layer: :implementation, count: counts[:cdef]) if reference),
      *document_tabs(counts, {}),
      SEPARATOR,
      (Tab.new(key: :people, label: "People", path: admin_users_path, icon: "user") if current_user&.instance_administrator?),
      (Tab.new(key: :settings, label: "Settings", path: admin_organizations_path, icon: "settings") if admin_access?)
    ].compact.then { |tabs| tidy_separators(tabs) }
  end

  def shell_boundary_tabs(boundary)
    counts = shell_nav_counts(boundary)
    scoped = { BoundaryScopedList::PARAM => boundary.id }
    baseline = boundary.profile_document
    [
      Tab.new(key: :overview, label: "Overview", path: authorization_boundary_path(boundary), icon: "house"),
      SEPARATOR,
      (Tab.new(key: :baselines, label: "Baseline", path: profile_document_path(baseline), icon: "list-checks",
               layer: :controls) if baseline && controls_publicly_accessible?),
      Tab.new(key: :ssp, label: "SSP", path: ssp_documents_path(scoped), icon: "file-text",
              layer: :implementation, count: counts[:ssp]),
      (Tab.new(key: :cdef, label: "CDEFs", path: cdef_documents_path(scoped), icon: "puzzle",
               layer: :implementation, count: counts[:cdef]) if controls_publicly_accessible?),
      *document_tabs(counts, scoped),
      SEPARATOR,
      Tab.new(key: :leveraged, label: "Leveraged POA&Ms", path: leveraged_poam_documents_path(scoped),
              icon: "link", layer: :enterprise)
    ].compact.then { |tabs| tidy_separators(tabs) }
  end

  # #1291 — the switcher's list: every boundary the viewer can reach, grouped
  # by organization (boundaries with none in their own group, last), and the
  # recently used ones first. Recent ids come from a cookie and are resolved
  # through the same visible set, so an id the viewer cannot reach is dropped.
  #
  # #1246 — a viewer whose boundaries all sit in one organization (and who is
  # not an instance administrator, who keeps the full tree) gets them as one
  # list: the breadcrumb already names the organization.
  Switcher = Struct.new(:recent, :groups, :flat, keyword_init: true)
  NO_ORGANIZATION = "No organization"

  def shell_switcher
    @shell_switcher ||= begin
      visible = AuthorizationBoundary.visible_to(current_user).includes(:organization).order(:name).to_a
      by_id = visible.index_by(&:id)
      recent = shell_recent_boundary_ids.filter_map { |id| by_id[id] }
      groups = visible.group_by { |b| b.organization&.name }
                      .sort_by { |name, _| [ name.nil? ? 1 : 0, name.to_s.downcase ] }
                      .map { |name, list| [ name || NO_ORGANIZATION, list ] }
      flat = groups.size == 1 && !current_user&.instance_administrator? && SparcConfig.any_auth_enabled?
      Switcher.new(recent: recent, groups: groups, flat: flat)
    end
  end

  # Where choosing `boundary` takes the viewer: the same list narrowed to it
  # when the page is a list with the Boundary filter, otherwise its own page.
  # nil = "All boundaries".
  def shell_switch_path(boundary)
    if boundary_filter
      query = request.query_parameters.except("page", BoundaryScopedList::PARAM.to_s)
      query = query.merge(BoundaryScopedList::PARAM.to_s => boundary.id) if boundary
      url_for(query.merge(only_path: true))
    else
      boundary ? authorization_boundary_path(boundary) : authorization_boundaries_path
    end
  end

  # Polyline points for a sparkline of `values` in a width x height box,
  # oldest on the left. A flat line at the bottom when nothing happened.
  def sparkline_points(values, width: 140, height: 32)
    values = Array(values)
    return "" if values.size < 2

    top = [ values.max, 1 ].max
    step = (width - 2).to_f / (values.size - 1)
    values.each_with_index.map do |v, i|
      format("%.1f,%.1f", 1 + (i * step), height - 2 - (v.to_f / top * (height - 4)))
    end.join(" ")
  end

  # Status chip modifier for a boundary status (ApplicationHelper's map, in the
  # #950 intents the chip uses).
  def boundary_status_chip(status)
    { "success" => "positive", "danger" => "danger", "info" => "info" }.fetch(ab_status_variant(status), "neutral")
  end

  private

  def document_tabs(counts, params)
    [
      Tab.new(key: :sap, label: "SAPs", path: sap_documents_path(params), icon: "clipboard-list",
              layer: :assessment, count: counts[:sap]),
      Tab.new(key: :sar, label: "SARs", path: sar_documents_path(params), icon: "chart-line",
              layer: :assessment, count: counts[:sar]),
      Tab.new(key: :evidence, label: "Evidence", path: evidences_path(params), icon: "paperclip",
              layer: :assessment, count: counts[:evidence]),
      Tab.new(key: :poam, label: "POA&Ms", path: poam_documents_path(params), icon: "flag",
              layer: :assessment, count: counts[:poam])
    ]
  end

  # Once per request per boundary (nil = everything reachable).
  def shell_nav_counts(boundary)
    @shell_nav_counts ||= {}
    @shell_nav_counts[boundary&.id] ||= BoundaryNavCounts.for(boundary, current_user)
  end

  # No separator at either end or twice in a row, whatever was hidden.
  def tidy_separators(tabs)
    tabs.each_with_object([]) { |t, out| out << t unless t == SEPARATOR && (out.empty? || out.last == SEPARATOR) }
        .then { |out| out.last == SEPARATOR ? out[0...-1] : out }
  end
end
