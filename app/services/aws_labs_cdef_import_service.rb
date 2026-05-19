require "tempfile"

# Issue #466 — Orchestrates the runtime import of AWS Labs Component
# Definitions into the SPARC CdefDocument catalog.
#
# Flow:
#   1. Bail unless SPARC_AWS_LABS_CDEF_ENABLED is true.
#   2. List all .json files under component-definitions/ via the GitHub
#      Trees API (ETag-conditional — no work when nothing has changed).
#   3. Fetch + lightly parse each blob to read metadata.oscal-version and
#      metadata.version. Filter to OSCAL spec versions SPARC supports.
#   4. Group by (service_path, oscal-version); keep the highest
#      metadata.version per group.
#   5. For each kept file, dedupe against existing rows on (source_url,
#      source_sha). When source_sha changes for an existing source_url,
#      mark the prior row superseded and create a new one.
#   6. Clones (cloned_from_id IS NOT NULL) are never touched.
#
# NIST mapping comments:
#   - RA-3(1) Supply Chain Risk Assessment: external CDEF source enumeration
#   - CA-2 Control Assessments: automated baseline refresh
#   - CM-8 Component Inventory: source_url + source_sha provenance
#   - SR-3 Supply Chain Controls: blob SHA-based integrity verification
#   - SA-15 Development Process: third-party content lifecycle
class AwsLabsCdefImportService
  Result = Struct.new(
    :discovered, :imported, :skipped_unchanged, :superseded, :errors,
    keyword_init: true
  ) do
    def to_s
      "discovered=#{discovered} imported=#{imported} " \
        "skipped_unchanged=#{skipped_unchanged} superseded=#{superseded} " \
        "errors=#{errors.length}"
    end
  end

  def initialize(client: AwsLabsCdefSourceClient.new,
                 allowed_oscal_versions: SparcConfig.aws_labs_oscal_versions,
                 logger: Rails.logger)
    @client = client
    @allowed_oscal_versions = Array(allowed_oscal_versions).map(&:to_s).map(&:strip).reject(&:blank?)
    @logger = logger
  end

  def run(force: false)
    unless SparcConfig.aws_labs_cdef_enabled?
      @logger.info("[AwsLabsCdefImportService] SPARC_AWS_LABS_CDEF_ENABLED=false; skipping")
      return Result.new(discovered: 0, imported: 0, skipped_unchanged: 0, superseded: 0, errors: [])
    end

    tree_entries = @client.list_component_definition_files
    if tree_entries.nil? && !force
      @logger.info("[AwsLabsCdefImportService] Upstream tree unchanged (304); nothing to do")
      return Result.new(discovered: 0, imported: 0, skipped_unchanged: 0, superseded: 0, errors: [])
    end

    # When force, we may not have a tree; refetch by clearing the ETag.
    tree_entries ||= begin
      Rails.cache.delete("aws_labs_cdef:etag:tree:#{SparcConfig.aws_labs_cdef_repo}:#{SparcConfig.aws_labs_cdef_branch}")
      @client.list_component_definition_files
    end

    commit_sha = @client.current_commit_sha
    candidates = build_candidates(tree_entries)
    @logger.info("[AwsLabsCdefImportService] Discovered #{candidates.length} candidate CDEFs after version filtering")

    imported = 0
    skipped_unchanged = 0
    superseded = 0
    errors = []

    candidates.each do |candidate|
      result = import_one(candidate, commit_sha: commit_sha)
      case result
      when :imported then imported += 1
      when :superseded_and_imported then imported += 1; superseded += 1
      when :skipped_unchanged then skipped_unchanged += 1
      end
    rescue => e
      @logger.error("[AwsLabsCdefImportService] Failed to import #{candidate[:path]}: #{e.class} #{e.message}")
      errors << { path: candidate[:path], error: "#{e.class}: #{e.message}" }
    end

    Result.new(discovered: tree_entries.length,
               imported: imported,
               skipped_unchanged: skipped_unchanged,
               superseded: superseded,
               errors: errors)
  end

  private

  # For each tree entry: fetch metadata only (parse JSON, read
  # metadata.oscal-version + metadata.version), filter by allowed OSCAL
  # versions, then keep the highest metadata.version per (service_path,
  # oscal-version).
  def build_candidates(tree_entries)
    fetched = tree_entries.map do |entry|
      file = @client.fetch_file(path: entry["path"])
      data = JSON.parse(file[:content])
      meta = data.dig("component-definition", "metadata") || {}
      next nil if meta["oscal-version"].blank?
      next nil if @allowed_oscal_versions.any? && !@allowed_oscal_versions.include?(meta["oscal-version"])

      {
        path: file[:path],
        sha: file[:sha],
        html_url: file[:html_url],
        content: file[:content],
        oscal_version: meta["oscal-version"],
        metadata_version: meta["version"].to_s,
        service_dir: service_dir_for(file[:path])
      }
    rescue JSON::ParserError => e
      @logger.warn("[AwsLabsCdefImportService] Skipping #{entry['path']}: invalid JSON (#{e.message})")
      nil
    end.compact

    fetched.group_by { |c| [ c[:service_dir], c[:oscal_version] ] }
           .map { |_, group| highest_version(group) }
  end

  def service_dir_for(path)
    # component-definitions/<service>/<file>.json → "<service>"
    parts = path.split("/")
    parts.length >= 3 ? parts[1] : parts.last.to_s.sub(/\.json\z/, "")
  end

  def highest_version(group)
    group.max_by { |c| version_tuple(c[:metadata_version]) }
  end

  # "1.0.4" → [1, 0, 4]. Falls back to a sortable zero-array on garbage so
  # entries with malformed versions sort lowest, not raise.
  def version_tuple(str)
    str.to_s.scan(/\d+/).map(&:to_i).then { |t| t.empty? ? [ 0 ] : t }
  end

  def import_one(candidate, commit_sha:)
    # Dedup: same source_url + same source_sha → skip.
    existing = CdefDocument.aws_labs_sourced
      .where("import_metadata->>'source_url' = ?", candidate[:html_url])
      .order(created_at: :desc)
      .first

    if existing && existing.import_metadata["source_sha"] == candidate[:sha]
      @logger.debug("[AwsLabsCdefImportService] Unchanged: #{candidate[:path]}")
      return :skipped_unchanged
    end

    write_through_parser(candidate, commit_sha: commit_sha)

    if existing
      existing.update!(
        import_metadata: existing.import_metadata.merge(
          "superseded_at" => Time.current.iso8601,
          "superseded_by_sha" => candidate[:sha]
        )
      )
      :superseded_and_imported
    else
      :imported
    end
  end

  # The existing CdefJsonParserService reads the file from disk and writes
  # the document's import_metadata itself. We let it run, then merge our
  # AWS provenance fields on top so future refreshes can dedupe correctly.
  def write_through_parser(candidate, commit_sha:)
    document = CdefDocument.create!(
      name: derive_name(candidate),
      status: "processing",
      cdef_type: "custom",
      file_type: "json",
      lifecycle_status: "published",
      globally_available: true,
      published: "true"
    )

    Tempfile.create([ "aws-labs-cdef-", ".json" ]) do |tmp|
      tmp.binmode
      tmp.write(candidate[:content])
      tmp.flush
      CdefJsonParserService.new(document, tmp.path).parse
    end

    document.reload
    document.update!(
      import_metadata: (document.import_metadata || {}).merge(
        "source_type" => "aws_labs",
        "source_repo" => SparcConfig.aws_labs_cdef_repo,
        "source_branch" => SparcConfig.aws_labs_cdef_branch,
        "source_path" => candidate[:path],
        "source_url" => candidate[:html_url],
        "source_sha" => candidate[:sha],
        "source_commit_sha" => commit_sha,
        "source_oscal_version" => candidate[:oscal_version],
        "source_metadata_version" => candidate[:metadata_version],
        "fetched_at" => Time.current.iso8601,
        "locked" => true
      ),
      status: "completed"
    )
    enrich_with_nist_mappings!(document)
    document
  end

  # Issue #491 — Walks the freshly-parsed CdefControls and looks up each
  # AWS Security Hub control_id (e.g., "IAM.3", "S3.5") in the
  # aws_security_hub_to_nist Converter. Persists the lookup result as
  # CdefControlField rows so heatmap / OSCAL export / SSP cross-reference
  # consumers can resolve to NIST 800-53 rev5 control identifiers.
  #
  # We do NOT mutate the control_id column itself -- the AWS upstream
  # identifier remains the canonical reference for the row. The NIST
  # mapping is additive metadata, with the SecHub id always recoverable.
  #
  # Fields written per CdefControl when a mapping exists:
  #   - aws_security_hub_id  : the original SecHub identifier (provenance)
  #   - nist_oscal_ids       : comma-joined OSCAL ids (audit / display)
  #   - nist_primary_id      : the lowest-sorted NIST id (primary for grouping)
  #   - nist_mapping_source  : "aws_direct" or "mitre_fallback" -- which
  #                            data source produced the mapping
  def enrich_with_nist_mappings!(document)
    converter = Converter.find_by(converter_type: "aws_security_hub_to_nist")
    unless converter
      @logger.debug("[AwsLabsCdefImportService] No aws_security_hub_to_nist Converter; skipping NIST enrichment")
      return
    end

    enriched_count = 0
    document.cdef_controls.find_each do |control|
      sec_hub_id = control.control_id.to_s
      next unless sec_hub_id.match?(/\A[A-Za-z][A-Za-z0-9]*\.\d+\z/)

      entries = converter.converter_entries.where(source_id: sec_hub_id)
      next if entries.empty?

      nist_ids = entries.pluck(:target_id).uniq.sort
      mapping_source = entries.pluck(:category).uniq.first

      upsert_cdef_field!(control, "aws_security_hub_id", sec_hub_id, editable: false)
      upsert_cdef_field!(control, "nist_oscal_ids", nist_ids.join(","), editable: false)
      upsert_cdef_field!(control, "nist_primary_id", nist_ids.first, editable: false)
      upsert_cdef_field!(control, "nist_mapping_source", mapping_source, editable: false)
      enriched_count += 1
    end

    if enriched_count > 0
      @logger.info("[AwsLabsCdefImportService] Enriched #{enriched_count} controls with NIST mappings " \
                   "for document #{document.id} (#{document.name})")
    end
  end

  def upsert_cdef_field!(control, field_name, field_value, editable:)
    field = control.cdef_control_fields.find_or_initialize_by(field_name: field_name)
    field.update!(field_value: field_value, editable: editable)
  end

  def derive_name(candidate)
    # component-definitions/s3/s3-cd.json → "AWS s3 (oscal 1.1.2)"
    "AWS #{candidate[:service_dir]} (oscal #{candidate[:oscal_version]})"
  end
end
