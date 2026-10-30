# frozen_string_literal: true

# #887 §5 — one definition of "what does browsing CDEFs mean".
#
# The browse rules started life inline in CdefDocumentsController, which made
# the UI the only place that knew a search should reach component regions, or
# that `partition` narrows a document through its components. An API consumer
# asking for the same thing got a different answer — the parity gap #887 called
# out. Both controllers now go through here, so a facet cannot be added to one
# surface and quietly missed on the other.
#
# Facets resolve through the component index and fold back to documents, so
# they INTERSECT the free-text search rather than replacing it: `?q=iam` plus
# `?partition=aws-us-gov` means "IAM, in GovCloud", not "IAM or GovCloud".
class CdefBrowseQuery
  # 1.18.0-rf #1300 adds source (CdefDocument::SOURCES), family (NIST
  # control family, e.g. AC) and component_type ("applies to").
  FACETS = %i[partition capability checks source family component_type].freeze

  FACET_LABELS = {
    partition: "Partition",
    capability: "Capability",
    checks: "Automated checks",
    source: "Source",
    family: "Family",
    component_type: "Applies to"
  }.freeze

  def initialize(params, scope: CdefDocument.order(created_at: :desc))
    @params = params
    @scope = scope
  end

  def documents
    result = @scope
    result = apply_boundary(result)
    result = apply_search(result)
    apply_facets(result)
  end

  # The facets actually in play, for the API to echo back so a caller can tell
  # what narrowed the result set without re-parsing the query string.
  def applied_facets
    FACETS.index_with { |key| @params[key].presence }.compact
  end

  # 1.18.0-rf #1300 — the dropdowns for the list's left column (the shared
  # filter form). Choices come from the CDEFs in `@scope`, so the list never
  # offers a family or component type it does not hold (within the
  # boundary the list is filtered to). Source is the list's
  # status tabs, so it has no dropdown.
  def filter_fields
    docs = apply_boundary(@scope).reorder(nil).select(:id)
    families = CdefControl.where(cdef_document_id: docs)
                          .distinct.pluck(Arel.sql(CdefControl::FAMILY_SQL))
                          .grep(CdefControl::NIST_FAMILY).sort
    types = CdefComponent.where(cdef_document_id: docs).where.not(component_type: [ nil, "" ])
                         .distinct.pluck(:component_type).sort
    partitions = CdefComponent.where(cdef_document_id: docs).pluck(:partitions).flatten.uniq.sort
    [
      select_field(:family, families.map { [ _1, _1 ] }),
      select_field(:component_type, types.map { [ _1.humanize, _1 ] }),
      select_field(:partition, partitions.map { [ CdefComponent.partition_label(_1), _1 ] }),
      select_field(:checks, [ [ "With automated checks", "true" ], [ "Documentation only", "false" ] ])
    ].compact
  end

  private

  # #951 — "the CDEFs this boundary is using".
  #
  # The sidebar has linked here with `?authorization_boundary_id=` since #796,
  # and NOTHING read it: the facets are partition/capability/checks and the
  # default scope is every CdefDocument, so every boundary's "CDEFs" leaf listed
  # the whole instance. Measured before the fix — unfiltered 234, with the
  # parameter 234, with a bogus `cdef_type` 0, which is the control showing the
  # index does narrow on a parameter it actually supports.
  #
  # "Using" is the union of the two ways a CDEF becomes the boundary's:
  #
  #   1. Linked to one of the boundary's ENVIRONMENTS (`BoundaryCdefDocument`).
  #      This is the selection itself — `AtoPackageService` step 2 writes it,
  #      and step 3 hands the same ids to `SspWizardService`, so it is upstream
  #      of the SSP rather than a parallel fact.
  #   2. Consumed by a component of the boundary's SSP.
  #
  # Both, because neither alone is complete. `SspWizardService` can be called
  # without the ATO wizard, which creates SspComponents carrying a
  # `cdef_document_id` and no BoundaryCdefDocument row; and a CDEF can be
  # selected for an environment before the SSP materialises its components. A
  # filter that missed either would tell someone they are not using a component
  # definition they are using, which is worse than showing one too many.
  #
  # Absent the parameter the scope is untouched, so Implementation ->
  # Component Definitions keeps listing every CDEF, which is what that screen is
  # for: the boundary view shows what you use, the unscoped view is where you
  # find more to add.
  def apply_boundary(scope)
    # #1202 — the rule lives in BoundaryScopedList, shared with the sidebar and
    # every other document list; it is unchanged from the #951 union above.
    BoundaryScopedList.narrow_params(:cdef, scope, @params)
  end

  # #672 filtered on name and description only, so an obvious query like
  # `us-east` or `AC-2` returned nothing — those facts live on the component
  # index, not on the document. Match either.
  def apply_search(scope)
    term = @params[:q]
    return scope if term.blank?

    scope.where(id: scope.model.search_text(term).select(:id))
         .or(scope.where(id: CdefComponent.search(term).select(:cdef_document_id)))
  end

  def select_field(key, choices)
    return if choices.size < 2 && @params[key].blank?

    { key: key, label: FACET_LABELS.fetch(key), type: :select, choices: choices, value: @params[key] }
  end

  def apply_facets(scope)
    scope = scope.with_source(@params[:source]) if @params[:source].present?
    if @params[:family].present?
      scope = scope.where(id: CdefControl.in_family(@params[:family]).select(:cdef_document_id))
    end
    if @params[:component_type].present?
      scope = scope.where(id: CdefComponent.where(component_type: @params[:component_type]).select(:cdef_document_id))
    end

    if @params[:partition].present?
      scope = scope.where(id: CdefComponent.in_partition(@params[:partition]).select(:cdef_document_id))
    end

    if @params[:capability].present?
      scope = scope.where(id: CdefComponent.with_capability(@params[:capability]).select(:cdef_document_id))
    end

    # Documentation-only vs contributes-to-continuous-assessment is the question
    # behind this one, so it is a boolean rather than a count.
    if @params[:checks].present?
      wanted = ActiveModel::Type::Boolean.new.cast(@params[:checks])
      matching = CdefComponent.where(has_checks: true).select(:cdef_document_id)
      scope = wanted ? scope.where(id: matching) : scope.where.not(id: matching)
    end

    scope
  end
end
