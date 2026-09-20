# frozen_string_literal: true

# Issue #1103 — regions, on the upload path.
#
# AWS publishes regions as their OWN component definition. From AWS's
# COMPONENTS.md: `aws_regions.oscal.json` "contains one OSCAL component for each
# AWS Region", and a service component carries "references to AWS documentation
# and region availability (via `provided-by` links to the AWS Regions component
# definition)". The dependency crosses files by design, so uploading regions
# separately is the documented workflow, not an edge case.
#
# CdefComponentIndexer#region_map resolves those `provided-by` fragments against
# region components ALREADY INDEXED, across documents. A service indexed before
# any regions CDEF exists therefore resolves zero regions — it does not fail, it
# just silently stores nothing.
#
# AwsLabsCdefImportService solved this for its own path twice over: `regions_first`
# orders the regions CDEF ahead of the services, and `repair_regions` re-indexes
# a service that was imported too early. Both were private to that service, and
# neither had a single caller anywhere else.
#
# The upload path had neither. `handle_multi_file_upload` iterates files in
# browser-supplied order and enqueues a DocumentConversionJob per file, so the
# ordering is not merely unsorted — it is ASYNCHRONOUS, and completion order is
# not guaranteed even when the user picks the regions file first. A service
# uploaded before its regions CDEF kept empty `region_ids` permanently: nothing
# re-indexed it, and the only recovery was the `cdef:reindex` rake task, which
# is not reachable from the UI at all.
#
# ── Both directions ────────────────────────────────────────────────────────
#
# Whichever file arrives second completes the pair:
#
#   A. a REGIONS CDEF arrives -> re-index the services still holding no regions
#   B. a SERVICE CDEF arrives -> re-index it if regions already exist and it
#      resolved none
#
# NIST controls: CM-8 (the component inventory reflects what was actually
# imported, rather than what happened to be imported first).
class CdefRegionReindexService
  def initialize(logger: Rails.logger)
    @logger = logger
  end

  # `content` is the already-parsed OSCAL for `document` when the caller has it
  # in hand (the import paths do), which saves resolving the source again.
  # Returns the number of documents re-indexed.
  def call(document, content: nil)
    data = normalize(content) || resolve(document)
    return 0 if data.nil?

    if defines_regions?(data)
      repair_dependents(document)
    else
      repair_self(document, data)
    end
  end

  # True when this document defines the region components other CDEFs point at.
  # Same rule as AwsLabsCdefImportService#defines_regions?, applied to content
  # rather than to a repository candidate.
  def defines_regions?(data)
    Array(data.dig("component-definition", "components")).any? { |c| c["type"] == "region" }
  end

  private

  # Direction A. A regions CDEF just landed, so every service that resolved
  # nothing can now resolve something.
  #
  # Scoped to documents NOT sourced from AWS Labs: that population is ordered by
  # `regions_first` and repaired by `repair_regions` on its own importer, and
  # re-indexing it here would make CdefSourceResolver re-FETCH each document
  # over the network — hundreds of requests inside an upload job. Uploaded CDEFs
  # keep their attachment, so they resolve from disk.
  def repair_dependents(regions_document)
    candidates = CdefDocument
      .where.not(id: regions_document.id)
      .where("import_metadata->>'source_type' IS DISTINCT FROM ?", "aws_labs")

    repaired = 0
    candidates.find_each(batch_size: 50) do |document|
      next if document.cdef_components.where.not(region_ids: []).exists?
      next unless document.cdef_components.exists?

      repaired += 1 if reindex(document)
    end

    if repaired.positive?
      @logger.info("[CdefRegionReindexService] #{regions_document.name} defines regions; " \
                   "re-indexed #{repaired} document(s) that had resolved none")
    end
    repaired
  end

  # Direction B. A service arrived after its regions.
  #
  # Deliberately narrow, matching the rule AwsLabsCdefImportService already
  # used: only when region components exist AND this document resolved none. A
  # service that genuinely has no regions re-indexes once per import, which is
  # bounded and self-correcting; a service that HAS regions is left alone.
  def repair_self(document, data)
    return 0 unless CdefComponent.where(component_type: "region").exists?
    return 0 if document.cdef_components.where.not(region_ids: []).exists?

    reindex(document, data) ? 1 : 0
  end

  # Best-effort, and never allowed to take down the import that triggered it.
  #
  # The `requires_new: true` SAVEPOINT is load-bearing for the same reason it is
  # in AwsLabsCdefImportService#reindex_components: rescuing a database error
  # inside a Postgres transaction without a savepoint poisons the transaction,
  # and every later statement then fails naming neither the record nor the cause
  # (#963, audited in #968).
  def reindex(document, content = nil)
    data = content || resolve(document)
    return false if data.nil?

    ActiveRecord::Base.transaction(requires_new: true) do
      CdefComponentIndexer.new(document, data).index!
    end
    true
  rescue StandardError => e
    @logger.warn("[CdefRegionReindexService] reindex failed for #{document.id}: #{e.class}: #{e.message}")
    # A log line is not a contract (#968 item 4) — the existing degradation
    # marker is the surface an operator actually looks at.
    document.record_component_index_failure!(e)
    false
  end

  # Callers hand content in two shapes: the import paths carry the RAW JSON
  # string they fetched, the parser carries the already-parsed Hash.
  # CdefComponentIndexer accepts either, so this must too — passing the string
  # straight through reached `.dig` on a String.
  def normalize(content)
    return nil if content.nil?
    return content unless content.is_a?(String)

    JSON.parse(content)
  rescue JSON::ParserError => e
    @logger.warn("[CdefRegionReindexService] unparseable content: #{e.class}: #{e.message}")
    nil
  end

  def resolve(document)
    CdefSourceResolver.new(document, logger: @logger).oscal
  rescue StandardError => e
    @logger.warn("[CdefRegionReindexService] could not resolve source for #{document.id}: #{e.class}: #{e.message}")
    nil
  end
end
