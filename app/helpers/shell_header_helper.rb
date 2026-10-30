# frozen_string_literal: true

# 1.18.0-rf #1295 — the header's menus under SPARC_NAV_SHELL. Each entry is
# shown exactly when its screen admits the viewer, through the predicates
# today's menus already use; nothing here decides access on its own.
#
#   Create   the "New" actions of the homepage cards (HomeHelper#home_layer_groups),
#            so the header never offers a create the Overview would not
#   Library  the shared-library screens, which belong to no boundary
#   Help     help for this page, the guides, the operator's links, About, OSCAL
#
# NIST SP 800-53 Rev 5: AC-3 Access Enforcement — a menu offers only what the
# viewer may open.
module ShellHeaderHelper
  MenuItem = Struct.new(:key, :label, :path, :icon, keyword_init: true)

  # The Create menu's order, and its labels (the cards' titles are plural).
  CREATE_ITEMS = {
    authorization_boundaries: "Boundary", profile_documents: "Baseline", ssp_documents: "SSP",
    cdef_documents: "CDEF", sap_documents: "SAP", sar_documents: "SAR", evidences: "Evidence",
    poam_documents: "POA&M"
  }.freeze

  # The new-document forms that preselect the boundary from
  # `?authorization_boundary_id=` (shared/_boundary_picker; evidences#new).
  BOUNDARY_PRESELECT = %i[ssp_documents sap_documents sar_documents evidences poam_documents].freeze

  def shell_create_items(boundary = nil)
    cards = home_layer_groups.flat_map { |g| g[:cards] }.index_by { |c| c[:key] }
    CREATE_ITEMS.filter_map do |key, label|
      card = cards[key]
      next unless card && card[:can_create]

      path = card[:new_path]
      path = "#{path}?#{{ BoundaryScopedList::PARAM => boundary.id }.to_query}" if boundary && BOUNDARY_PRESELECT.include?(key)
      MenuItem.new(key: key, label: label, path: path, icon: card[:icon])
    end
  end

  def shell_library_items
    reference = controls_publicly_accessible?
    member = !SparcConfig.any_auth_enabled? || signed_in?
    [
      (MenuItem.new(key: :control_catalogs, label: "Control Catalogs", path: control_catalogs_path, icon: "library") if reference),
      (MenuItem.new(key: :profile_documents, label: "Baselines", path: profile_documents_path, icon: "list-checks") if reference),
      (MenuItem.new(key: :control_mappings, label: "Mappings", path: control_mappings_path, icon: "arrow-left-right") if reference),
      (MenuItem.new(key: :cdef_documents, label: "Component Definitions", path: cdef_documents_path, icon: "puzzle") if reference),
      (MenuItem.new(key: :converters, label: "Converters", path: converters_path, icon: "replace") if reference),
      (MenuItem.new(key: :authoritative_sources, label: "Authoritative Sources", path: authoritative_sources_path,
                    icon: "scroll-text") if member && can_read_authoritative_sources?),
      (MenuItem.new(key: :promotion_queue, label: "Promotion Queue", path: promotion_queue_index_path,
                    icon: "arrow-up-from-line") if member),
      (MenuItem.new(key: :leveraged_poam_documents, label: "Leveraged POA&Ms", path: leveraged_poam_documents_path,
                    icon: "flag") if member),
      (MenuItem.new(key: :federation_peers, label: "Federation Peers", path: federation_peers_path,
                    icon: "link") if can_federate?)
    ].compact
  end

  # The review-queue indicator: nil when the viewer approves nothing, else the
  # number of documents waiting for them (ReviewQueue, the screen's own list).
  def shell_review_queue_count
    return @shell_review_queue_count if defined?(@shell_review_queue_count)

    @shell_review_queue_count =
      (ReviewQueue.approvable_for(current_user).size if ReviewQueue.approver?(current_user))
  end

  # Help & guides for the Help menu: Getting Oriented first, then the Help
  # Center, then every other guide (the sidebar's order, #796).
  def shell_help_guides
    sidebar_help_guides.reject { |g| g.slug == "getting-oriented" }
  end
end
