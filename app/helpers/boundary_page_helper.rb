# frozen_string_literal: true

# #1251 — the authorization boundary page.
module BoundaryPageHelper
  # Where a Boundary Completeness row's work is done, and whether this person
  # may do it there.
  #
  #   path          the screen in SPARC that does the work
  #   prerequisite  a label when the row cannot be worked yet and the link leads
  #                 to what it needs first ("Add SSP first"); nil otherwise
  CompletenessAction = Struct.new(:path, :prerequisite, keyword_init: true)

  ADD_SSP_FIRST = "Add SSP first"

  # The ONE mapping from a readiness section key to the place its work is done.
  # It lives in the screen, not in BoundaryReadinessService: the service also
  # answers /api/v1/authorization_boundaries/:id/readiness, and web links do not
  # belong in an API response.
  #
  # Returns nil when there is nowhere this person may act: each link is offered
  # only to someone the target action admits, by the key that action enforces
  # (#1247: a link that always refuses is not navigation).
  def completeness_action(section, boundary)
    ssp = boundary.ssp_document

    case section[:key].to_sym
    when :personnel
      completeness_link(new_authorization_boundary_membership_path(boundary),
                        boundary_permission?("authorization_boundaries.manage_members", boundary))
    when :classification
      ssp_work(boundary, ssp) { enrich_ssp_document_path(ssp, anchor: "info-types-container") }
    when :profile
      completeness_link(edit_authorization_boundary_path(boundary), can_edit_boundary?(boundary))
    when :ssp
      if ssp
        completeness_link(ssp_document_path(ssp), boundary_permission?("ssp.read", boundary))
      else
        completeness_link(attach_document_authorization_boundary_path(boundary, type: "ssp"), can_edit_boundary?(boundary))
      end
    when :components
      ssp_work(boundary, ssp) { enrich_ssp_document_path(ssp, anchor: "components-container") }
    when :back_matter
      # The Back Matter section on this page; it renders only for a reader.
      completeness_link(authorization_boundary_path(boundary, anchor: "boundary-back-matter"),
                        can_read_boundary_back_matter?(boundary) && can_write_boundary_back_matter?(boundary))
    when :leveraged
      completeness_link(new_authorization_boundary_leveraged_authorization_path(boundary),
                        can_manage_leveraged_authorizations?(boundary))
    when :cdefs
      completeness_link(new_cdef_coverage_path(authorization_boundary_id: boundary.id),
                        !SparcConfig.any_auth_enabled? || current_user&.has_permission?("cdef.read"))
    when :evidence
      completeness_link(new_evidence_path(authorization_boundary_id: boundary.id),
                        boundary_permission?("evidence.write", boundary))
    when :scans
      # Findings Triage ingests scans; ingest needs evidence.write.
      completeness_link(triage_authorization_boundary_path(boundary), boundary_permission?("evidence.write", boundary))
    when :environments
      completeness_link(new_authorization_boundary_boundary_path(boundary), can_edit_boundary?(boundary))
    end
  end

  # The anchor of a link to a section on THIS page, or nil for a link elsewhere.
  # The page's collapse-memory controller opens that section on click.
  def same_page_anchor(path)
    path.to_s[/\A#{Regexp.escape(request.path)}#(.+)\z/, 1]
  end

  private

  def completeness_link(path, allowed, prerequisite: nil)
    CompletenessAction.new(path: path, prerequisite: prerequisite) if allowed
  end

  # Work done on the boundary's SSP. With no SSP, the link leads to attaching
  # one, labelled as the prerequisite it is.
  def ssp_work(boundary, ssp)
    if ssp
      completeness_link(yield, boundary_permission?("ssp.write", boundary))
    else
      completeness_link(attach_document_authorization_boundary_path(boundary, type: "ssp"),
                        can_edit_boundary?(boundary), prerequisite: ADD_SSP_FIRST)
    end
  end
end
