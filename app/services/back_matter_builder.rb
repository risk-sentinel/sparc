# Builds the OSCAL back-matter section for a document by merging
# resources from two persisted sources plus the SPARC identifier:
#
#   1. Authoritative BackMatterResource records (provider-published,
#      highest priority, instance-wide)
#   2. Managed/imported BackMatterResource records attached to this
#      document (resourceable: document) or linked through its
#      controls (ControlBackMatterLink)
#   3. SPARC identifier resource (persistent UUID per document)
#
# As of #583 all back-matter lives in the back_matter_resources table —
# the legacy `import_metadata["back_matter"]` stash has been promoted to
# first-class rows during import, so no JSON-stash merge is needed.
#
# Usage:
#   BackMatterBuilder.new(ssp_document).build
#   # => { "resources" => [...] }
#
class BackMatterBuilder
  def initialize(document)
    @document = document
  end

  def build
    resources = authoritative_resources + managed_resources + [ sparc_resource ]
    { "resources" => resources }
  end

  private

  # Authoritative resources (provider-published, highest priority) that THIS
  # document actually references. Cannot be overridden by managed resources.
  #
  # #959 — this used to be every authoritative resource in the instance, embedded
  # into every export, with no document, boundary or organization scoping. The
  # consequences were not what "included in all document exports" intended:
  #
  #   * Exports leaked instance state into unrelated documents. Anything marked
  #     authoritative appeared in every SSP, SAP, SAR and POA&M the instance ever
  #     produced, including documents belonging to another organization or
  #     boundary — an information-disclosure question on a multi-tenant instance,
  #     not just noise.
  #   * Exports grew without bound, and could not be byte-reproducible: the same
  #     document exported before and after an unrelated resource was added
  #     produced different files. #845 needs committed OSCAL to regenerate
  #     identically to prove its fixtures have not drifted.
  #   * It is how test fixtures reached artifacts intended for the repo —
  #     measured at 96 rows of UI-smoke residue across the 12 reference
  #     artifacts, and the same class of leak once reached a public wiki
  #     screenshot.
  #
  # The rule is now the OSCAL one: back-matter exists to resolve references the
  # document makes, so a resource is carried when the document points at it.
  # Lineage is not a special case — a resource reaching an SSP through the
  # profile its boundary uses, or through a leveraged SSP, arrives as a control
  # link like any other, and control links are exactly what the exporters emit
  # as `{"href" => "#uuid"}` (see OscalSspExportService#468 and
  # OscalComponentDefinitionExportService#204).
  #
  # `spec/services/back_matter_reference_integrity_spec.rb` guards both
  # directions: nothing referenced may be missing, and nothing unreferenced may
  # be carried.
  def authoritative_resources
    # order(:id) so repeated exports of an unchanged document are identical;
    # an unordered relation is returned in whatever order Postgres chooses.
    @authoritative_resources ||= begin
      uuids = referenced_uuids
      if uuids.empty?
        []
      else
        BackMatterResource.active.where(source: "authoritative", uuid: uuids.to_a)
                          .order(:id)
                          .map(&:to_oscal_resource)
      end
    end
  end

  # Every back-matter UUID this document points at: resources attached directly
  # to the document, plus those linked to any of its controls. These are the two
  # sources the exporters turn into `href` references, so this set is exactly
  # what a reader of the exported file can follow.
  def referenced_uuids
    @referenced_uuids ||= (
      @document.back_matter_resources.active.pluck(:uuid) +
      control_linked_resources.pluck(:uuid)
    ).compact.to_set
  end

  def authoritative_uuids
    @authoritative_uuids ||= BackMatterResource.active.where(source: "authoritative")
                                                .pluck(:uuid).to_set
  end

  def managed_resources
    doc_resources = @document.back_matter_resources.active
                             .where.not(source: "authoritative")
                             .order(:id)
                             .map(&:to_oscal_resource)
    ctrl_resources = control_linked_resources.map(&:to_oscal_resource)
    # Exclude UUIDs already claimed by authoritative resources
    (doc_resources + ctrl_resources).uniq { |r| r["uuid"] }
                                    .reject { |r| authoritative_uuids.include?(r["uuid"]) }
  end

  # Resources linked to controls within this document (not directly
  # attached to the document as resourceable, but referenced via
  # ControlBackMatterLink join records).
  def control_linked_resources
    @control_linked_resources ||= begin
      control_types = []

      if @document.respond_to?(:cdef_controls)
        control_types << [ "CdefControl", @document.cdef_controls.select(:id) ]
      end
      if @document.respond_to?(:ssp_controls)
        control_types << [ "SspControl", @document.ssp_controls.select(:id) ]
      end
      if @document.respond_to?(:catalog_controls)
        control_types << [ "CatalogControl", @document.catalog_controls.select(:id) ]
      end

      return BackMatterResource.none if control_types.empty?

      conditions = control_types.map do |type, ids|
        ControlBackMatterLink.where(linkable_type: type, linkable_id: ids)
      end

      resource_ids = conditions.reduce { |acc, c| acc.or(c) }&.select(:back_matter_resource_id)
      resource_ids ? BackMatterResource.active.where(id: resource_ids) : BackMatterResource.none
    end
  end

  def sparc_resource
    @document.sparc_back_matter_resource
  end
end
