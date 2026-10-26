class HomeController < ApplicationController
  # #1243 — each layer card carries the count of the page its View button opens,
  # and that count is the one THAT page shows this user, so a badge never
  # promises a number its list does not hold and never reveals how many records
  # other organizations or boundaries keep (owner, 2026-10-22; AC-3 / AC-4).
  #
  #   SSP, SAP, SAR, Evidence, POA&M  each controller's own boundary_scoped
  #                                   declaration (BoundaryScopedDocument.index_relation)
  #   Authorization boundaries        AuthorizationBoundary.visible_to
  #   Catalogs, baselines, mappings,  the shared library: every record, as their
  #   CDEFs, converters               index pages count today. If those pages
  #                                   gain scoping, these follow.
  #   Organizations                   administrator screen; counted only for
  #                                   someone it admits (the card is hidden
  #                                   otherwise)
  #
  # The inventory tiles above the cards show these same counts, grouped by layer.
  def index
    @counts = {
      control_catalogs: ControlCatalog.count,
      profile_documents: ProfileDocument.count,
      control_mappings: ControlMapping.count,
      cdef_documents: CdefDocument.count,
      converters: Converter.count,
      ssp_documents: boundary_document_count(SspDocumentsController),
      sap_documents: boundary_document_count(SapDocumentsController),
      sar_documents: boundary_document_count(SarDocumentsController),
      evidences: boundary_document_count(EvidencesController),
      poam_documents: boundary_document_count(PoamDocumentsController),
      authorization_boundaries: AuthorizationBoundary.visible_to(current_user).count
    }
    @counts[:organizations] = Organization.count if helpers.admin_access?

    # The Families and Controls inventory tiles, from the expressions the
    # catalog page's own tiles use.
    @family_count  = ControlCatalog.family_count
    @control_count = ControlCatalog.control_count
  end

  def oscal_overview
    # Static informational page: renders its template, no data to load.
  end

  private

  def boundary_document_count(controller_class)
    BoundaryScopedDocument.index_relation(controller_class, current_user).count
  end
end
