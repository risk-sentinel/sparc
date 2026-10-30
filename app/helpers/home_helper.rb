# frozen_string_literal: true

module HomeHelper
  # The homepage cards, by OSCAL layer: title, list, "New" (only where the
  # create action would let the viewer through) and icon. ONE definition read
  # by the classic home page and by the organization Overview (1.18.0-rf,
  # behind SPARC_NAV_SHELL), so the two can never offer different screens.
  def home_layer_groups
    [
      {
        label: "Controls Layer",
        color: ApplicationHelper::COLOR_BLUE,
        cls: "sparc-heading-controls",
        layer: "controls",
        cards: [
          { key: :control_catalogs, title: "Control Catalogs", path: control_catalogs_path,
            new_path: new_control_catalog_path, can_create: can_write_catalogs?, icon: "library" },
          { key: :profile_documents, title: "Baselines / Profiles", path: profile_documents_path,
            new_path: new_profile_document_path, can_create: can_write_profiles?, icon: "list-checks" },
          { key: :control_mappings, title: "Control Mapping", path: control_mappings_path,
            new_path: new_control_mapping_path, can_create: can_write_mappings?, icon: "arrow-left-right" }
        ]
      },
      {
        label: "Implementation Layer",
        color: ApplicationHelper::COLOR_GREEN,
        cls: "sparc-heading-implementation",
        layer: "implementation",
        cards: [
          { key: :ssp_documents, title: "SSPs", path: ssp_documents_path,
            new_path: new_ssp_document_path, can_create: can_create_boundary_document?(SspDocumentsController), icon: "file-text" },
          { key: :cdef_documents, title: "CDEFs", path: cdef_documents_path,
            new_path: new_cdef_document_path, can_create: can_write_cdefs?, icon: "puzzle" },
          { key: :converters, title: "Converters", path: converters_path,
            new_path: new_converter_path, can_create: can_write_converters?, icon: "replace" }
        ]
      },
      {
        label: "Assessment Layer",
        color: ApplicationHelper::COLOR_CARROT,
        cls: "sparc-heading-assessment",
        layer: "assessment",
        cards: [
          { key: :sap_documents, title: "SAPs", path: sap_documents_path,
            new_path: new_sap_document_path, can_create: can_create_boundary_document?(SapDocumentsController), icon: "clipboard-list" },
          { key: :evidences, title: "Evidence", path: evidences_path,
            new_path: new_evidence_path, can_create: can_create_boundary_document?(EvidencesController), icon: "paperclip" },
          { key: :sar_documents, title: "SARs", path: sar_documents_path,
            new_path: new_sar_document_path, can_create: can_create_boundary_document?(SarDocumentsController), icon: "chart-line" },
          { key: :poam_documents, title: "POA&Ms", path: poam_documents_path,
            new_path: new_poam_document_path, can_create: can_create_boundary_document?(PoamDocumentsController), icon: "flag" }
        ]
      },
      {
        label: "Enterprise",
        color: ApplicationHelper::COLOR_PURPLE,
        cls: "sparc-heading-enterprise",
        layer: "enterprise",
        cards: [
          # An administrator screen: the card shows only where it would admit the user.
          ({ key: :organizations, title: "Organizations", path: admin_organizations_path,
             new_path: new_admin_organization_path, can_create: admin_access?, icon: "building-2" } if admin_access?),
          { key: :authorization_boundaries, title: "Auth Boundaries", path: authorization_boundaries_path,
            new_path: new_authorization_boundary_path, can_create: can_create_boundary?, icon: "layout-list" }
        ].compact
      }
    ]
  end

  # 1.18.0-rf — the organization Overview's lanes: the homepage cards above,
  # each with its count, plus two Enterprise routing boxes that live in the
  # Enterprise menu today. Each extra box shows exactly when its screen admits
  # the viewer (the same predicates as the menu), and offers "New" only when
  # the create action would.
  def org_overview_lanes(counts)
    extra = [
      ({ key: :federation_peers, title: "Federation Peers", path: federation_peers_path,
         new_path: new_federation_peer_path, can_create: can_federate?, icon: "link",
         count: FederationPeer.count } if can_federate?),
      ({ key: :authoritative_sources, title: "Authoritative Sources", path: authoritative_sources_path,
         can_create: false, icon: "scroll-text",
         count: BackMatterResource.authoritative_sources_for(current_user).count } if can_read_authoritative_sources?)
    ].compact

    home_layer_groups.map do |group|
      cards = group[:cards].map { |c| c.merge(count: counts.fetch(c[:key])) }
      cards += extra if group[:layer] == "enterprise"
      group.merge(cards: cards)
    end
  end

  # The rail: the boundaries the viewer reaches, most recently changed first.
  def org_overview_recent_boundaries(limit: 5)
    AuthorizationBoundary.visible_to(current_user).order(updated_at: :desc).limit(limit)
  end

  # The baselines those boundaries use, most used first: [[name, count], ...].
  def org_overview_baselines_in_use
    AuthorizationBoundary.visible_to(current_user).joins(:profile_document)
                         .group("profile_documents.name").count
                         .sort_by { |name, n| [ -n, name ] }.first(6)
  end
end
