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
  # consumed by a component of its SSP.
  #
  # 1.18.0-rf #1292 — plus the boundary's OWN CDEFs (scope tier :boundary).
  # CDEFs carry no boundary column; CdefScopeService records the boundary in
  # import_metadata and links the CDEF to each of the boundary's environments.
  # A boundary with no environments yet has nothing to link to, so its own
  # CDEFs fell out of its list. Own + global ones linked to it is the rule the
  # owner chose on #1287 (#929 scope semantics).
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

    own = scope.where(globally_available: false)
               .where("cdef_documents.import_metadata ->> ? = ?", CdefScopeService::METADATA_KEY, boundary_id.to_s)

    scope.where(id: selected_for_environments).or(scope.where(id: consumed_by_ssp)).or(own)
  end

  # 1.18.0-rf #1292 — POA&Ms of the systems a boundary LEVERAGES (#415): the
  # leveraged side of each LeveragedAuthorization the boundary holds.
  LEVERAGED_POAM = lambda do |scope, boundary_id|
    scope.where(authorization_boundary_id: LeveragedAuthorization.where(leveraging_boundary_id: boundary_id)
                                                                  .select(:leveraged_boundary_id))
  end

  # Documents attached to no boundary (`?authorization_boundary_id=none`), for
  # the types whose boundary is optional, so none becomes unreachable once a
  # list follows a boundary. Evidence with no boundary is global evidence.
  UNATTACHED = ->(scope) { scope.where(authorization_boundary_id: nil) }

  # 1.18.0-rf #1292 — how many records each boundary's list holds, for the
  # list's Boundary filter: { boundary_id => count } in ONE grouped query,
  # whatever the number of boundaries. Each is the grouped form of the rule
  # above it, so a count always equals narrow(type, scope, id).count; the
  # spec checks every type against every boundary. A boundary missing from
  # the hash has none (the hash's default).
  OWNED_COUNTS = lambda do |base|
    Hash.new(0).merge(base.where.not(authorization_boundary_id: nil).group(:authorization_boundary_id).count)
  end

  # Global evidence belongs to every boundary's list (EVIDENCE above).
  EVIDENCE_COUNTS = lambda do |base|
    owned = base.group(:authorization_boundary_id).count
    global = owned.delete(nil) || 0
    Hash.new(global).merge(owned.transform_values { |n| n + global })
  end

  # The three ways a CDEF belongs to a boundary (CDEF above) as
  # (boundary, cdef) pairs, counted once per CDEF.
  CDEF_COUNTS = lambda do |base|
    key = CdefScopeService::METADATA_KEY
    linked = BoundaryCdefDocument.joins(:boundary)
      .select("boundaries.authorization_boundary_id AS ab_id", "boundary_cdef_documents.cdef_document_id AS cdef_id")
    consumed = SspComponent.joins(:ssp_document).where.not(cdef_document_id: nil)
      .select("ssp_documents.authorization_boundary_id AS ab_id", "ssp_components.cdef_document_id AS cdef_id")
    own = CdefDocument.where(globally_available: false)
      .where("cdef_documents.import_metadata ->> ? ~ '^[0-9]+$'", key)
      .select(CdefDocument.sanitize_sql_array([ "(cdef_documents.import_metadata ->> ?)::bigint AS ab_id", key ]),
              "cdef_documents.id AS cdef_id")
    union = Arel::Nodes::As.new(
      Arel::Nodes::Grouping.new(Arel::Nodes::Union.new(Arel::Nodes::Union.new(linked.arel, consumed.arel), own.arel)),
      Arel.sql("pairs")
    )

    Hash.new(0).merge(
      CdefDocument.unscoped.from(union)
        .where("pairs.ab_id IS NOT NULL")
        .where("pairs.cdef_id IN (?)", base.select(:id))
        .group("pairs.ab_id").distinct.count("pairs.cdef_id")
    )
  end

  # Counted per LEVERAGING boundary (LEVERAGED_POAM above).
  LEVERAGED_POAM_COUNTS = lambda do |base|
    Hash.new(0).merge(
      LeveragedAuthorization
        .joins("INNER JOIN poam_documents ON poam_documents.authorization_boundary_id = leveraged_authorizations.leveraged_boundary_id")
        .where(PoamDocument.arel_table[:id].in(base.select(:id).arel))
        .group(:leveraging_boundary_id).distinct.count("poam_documents.id")
    )
  end

  # Sidebar order. `route` is the list's path helper; `model` is how Api::V1's
  # shared controller finds its rule from `document_class`; `unattached` is how
  # the type answers `none` (types without it have no boundary-less records).
  #
  # The last two are lists the sidebar does not link, but which follow the
  # current boundary (#1292) by the same rule.
  RULES = {
    cdef:           { model: "CdefDocument", route: :cdef_documents_path, narrow: CDEF, counts: CDEF_COUNTS },
    ssp:            { model: "SspDocument",  route: :ssp_documents_path,  narrow: OWNED, counts: OWNED_COUNTS,
                      unattached: UNATTACHED },
    sap:            { model: "SapDocument",  route: :sap_documents_path,  narrow: OWNED, counts: OWNED_COUNTS,
                      unattached: UNATTACHED },
    evidence:       { model: "Evidence",     route: :evidences_path,      narrow: EVIDENCE, counts: EVIDENCE_COUNTS,
                      unattached: UNATTACHED },
    sar:            { model: "SarDocument",  route: :sar_documents_path,  narrow: OWNED, counts: OWNED_COUNTS,
                      unattached: UNATTACHED },
    poam:           { model: "PoamDocument", route: :poam_documents_path, narrow: OWNED, counts: OWNED_COUNTS,
                      unattached: UNATTACHED },
    leveraged_poam: { model: nil, route: :leveraged_poam_documents_path, narrow: LEVERAGED_POAM,
                      counts: LEVERAGED_POAM_COUNTS, sidebar: false },
    cdef_coverage:  { model: "CdefCoverageRun", route: :cdef_coverage_index_path, narrow: OWNED,
                      counts: OWNED_COUNTS, unattached: UNATTACHED, sidebar: false }
  }.freeze

  # 1.18.0-rf #1292 — the value that is not a boundary id: records attached to
  # no boundary. No value at all means every record the caller may see.
  NONE = "none"

  # The types the boundary sidebar links, in its order.
  def types = RULES.reject { |_type, r| r[:sidebar] == false }.keys

  # `scope` narrowed to `boundary_id`'s documents of this type; unchanged when no
  # boundary is given. `none` keeps only records attached to no boundary, and
  # matches nothing for a type that cannot have any. Anything else that is not
  # an id matches nothing: an integer column reads "12abc" as boundary 12, and
  # the evidence rule would still add global evidence to a value that names no
  # boundary at all.
  def narrow(type, scope, boundary_id)
    value = boundary_id.to_s
    return scope if value.blank?
    return rule(type).fetch(:unattached, ->(s) { s.none }).call(scope) if value == NONE
    return scope.none unless value.match?(/\A\d+\z/)

    rule(type).fetch(:narrow).call(scope, boundary_id)
  end

  # Whether this type has records attached to no boundary (`none` can match).
  def unattached?(type) = rule(type).key?(:unattached)

  # { boundary_id => count } of `scope`'s records in each boundary's list, in
  # one query (the rule's `counts`). Never widens: it counts within `scope`.
  def counts_by_boundary(type, scope)
    rule(type).fetch(:counts).call(base(scope))
  end

  # `scope` as a plain id subquery, so the caller's eager loading and
  # DISTINCT never reach a GROUP BY or COUNT. A limit stays (with its order),
  # so the subquery holds exactly the scope's records.
  def base(scope)
    inner = scope.except(:includes, :preload, :eager_load, :select)
    inner = inner.except(:order) unless inner.limit_value || inner.offset_value
    scope.klass.where(id: inner.select(scope.klass.arel_table[:id]))
  end

  # The same, reading the boundary from request params.
  def narrow_params(type, scope, params)
    narrow(type, scope, params[PARAM].presence)
  end

  # The rule for a model class, for callers that know the class rather than the
  # type (Api::V1::DocumentBaseController#document_class).
  def type_for(model)
    RULES.find { |_type, r| r[:model].present? && r[:model] == model.name }&.first ||
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
