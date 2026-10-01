# frozen_string_literal: true

# #1202 — ONE definition of "this document type within a boundary".
#
# The boundary sidebar links every document list with `?authorization_boundary_id=`,
# and each list decided on its own what that meant. Three of them (SSP, SAP, SAR)
# never read it, so choosing a boundary showed every document the user could see,
# while their Api::V1 siblings filtered correctly — the link, the web list and the
# API each spelled the parameter independently and nothing tied them together.
#
# So everything reads it from here: the sidebar builds its links with `path`, the
# web lists and Api::V1 narrow with `narrow`, and the browse query objects that
# already filtered correctly (POA&M, Evidence, CDEF) delegate their boundary step
# to the same rule.
#
# Each rule returns EVERY document of its type in the boundary — a boundary holds
# many SAPs, SARs, POA&Ms, evidence and CDEFs (#1203 covers how many SSPs, SAPs and
# SARs a boundary should hold; this is only about which boundary they belong to).
#
# `narrow` only ever NARROWS the relation it is given. The caller passes the
# permission-scoped relation (`boundary_scoped_relation`, or the API's scoped
# collection), so a boundary the user cannot see yields nothing — this never
# re-derives, and can never widen, who may see what.
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (narrows within the caller's authorized scope)
#   AC-4 Information Flow Enforcement (one boundary's documents stay in its lists)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
module BoundaryScopedList
  extend self

  PARAM = :authorization_boundary_id

  # Owned by the boundary: a column on the document.
  OWNED = ->(scope, boundary_id) { scope.where(authorization_boundary_id: boundary_id) }

  # #951 — Evidence a boundary USES includes global evidence (no boundary):
  # leveraged, inherited or provider artifacts. Excluding it made a boundary look
  # as if it held less evidence than it does. Another boundary's evidence is never
  # included.
  EVIDENCE = ->(scope, boundary_id) { scope.where(authorization_boundary_id: [ boundary_id, nil ]) }

  # #951 — the CDEFs a boundary USES: linked to one of its environments, or
  # consumed by a component of its SSP. CDEFs are instance-level and carry no
  # boundary column, so there is nothing to match directly.
  CDEF = lambda do |scope, boundary_id|
    selected_for_environments = BoundaryCdefDocument
      .joins(:boundary)
      .where(boundaries: { authorization_boundary_id: boundary_id })
      .select(:cdef_document_id)

    consumed_by_ssp = SspComponent
      .joins(:ssp_document)
      .where(ssp_documents: { authorization_boundary_id: boundary_id })
      .where.not(cdef_document_id: nil)
      .select(:cdef_document_id)

    scope.where(id: selected_for_environments).or(scope.where(id: consumed_by_ssp))
  end

  # Sidebar order. `route` is the list's path helper; `model` is how Api::V1's
  # shared controller finds its rule from `document_class`.
  RULES = {
    cdef:     { model: "CdefDocument", route: :cdef_documents_path, narrow: CDEF },
    ssp:      { model: "SspDocument",  route: :ssp_documents_path,  narrow: OWNED },
    sap:      { model: "SapDocument",  route: :sap_documents_path,  narrow: OWNED },
    evidence: { model: "Evidence",     route: :evidences_path,      narrow: EVIDENCE },
    sar:      { model: "SarDocument",  route: :sar_documents_path,  narrow: OWNED },
    poam:     { model: "PoamDocument", route: :poam_documents_path, narrow: OWNED }
  }.freeze

  def types = RULES.keys

  # `scope` narrowed to `boundary_id`'s documents of this type; unchanged when no
  # boundary is given.
  def narrow(type, scope, boundary_id)
    return scope if boundary_id.blank?

    rule(type).fetch(:narrow).call(scope, boundary_id)
  end

  # The same, reading the boundary from request params.
  def narrow_params(type, scope, params)
    narrow(type, scope, params[PARAM].presence)
  end

  # The rule for a model class, for callers that know the class rather than the
  # type (Api::V1::DocumentBaseController#document_class).
  def type_for(model)
    RULES.find { |_type, r| r[:model] == model.name }&.first ||
      raise(ArgumentError, "no boundary rule for #{model.name}")
  end

  # The list URL for this type within `boundary` — what the sidebar links to.
  def path(type, boundary)
    Rails.application.routes.url_helpers.public_send(rule(type).fetch(:route), PARAM => boundary.id)
  end

  private

  def rule(type)
    RULES.fetch(type) { raise ArgumentError, "no boundary rule for #{type.inspect}" }
  end
end
