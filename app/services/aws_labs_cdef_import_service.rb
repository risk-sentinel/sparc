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
  OSCAL_VERSION = "oscal-version".freeze

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

  # The service key a repository path denotes — the one rule for turning an AWS
  # Labs file path into "which AWS service is this?".
  #
  # Public because #904's CdefServiceIndex has to derive the SAME key from the
  # `source_path` recorded here in order to match a deployed service to its
  # CDEF. It briefly had its own copy that handled only the flat layout, so
  # `component-definitions/s3/s3-cd.json` yielded "s3-cd" and matched nothing —
  # every service would have reported "needs a CDEF" forever, against the real
  # repository, with no error to notice. Two implementations of one rule is the
  # defect; this is the rule.
  #
  #   component-definitions/<service>/<file>.json → "<service>"   (upstream)
  #   component-definitions/<file>.json           → "<file>"      (flattened)
  def self.service_key_for_path(path)
    parts = path.to_s.split("/")
    key = parts.length >= 3 ? parts[1] : parts.last.to_s.sub(/\.oscal\.json\z/, "").sub(/\.json\z/, "")
    key.to_s.strip.downcase.presence
  end

  def initialize(client: AwsLabsCdefSourceClient.new,
                 allowed_oscal_versions: SparcConfig.aws_labs_oscal_versions,
                 logger: Rails.logger)
    @client = client
    @allowed_oscal_versions = Array(allowed_oscal_versions).map(&:to_s).map(&:strip).reject(&:blank?)
    @logger = logger
    # Reset per `run`; initialized here so a caller that exercises
    # `build_candidates` directly does not hit a nil.
    @fetch_errors = []
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
    # #939 — fetch-stage failures are collected rather than aborting the pass.
    @fetch_errors = []
    candidates = regions_first(build_candidates(tree_entries))
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
      else nil # import_one only returns the states above
      end
    # #968 — the rescued list is explicit, for the same reason the fetch loop
    # above states it: these are the ways SOMEONE ELSE'S content can be wrong.
    # A bare `rescue =>` caught those identically to a NoMethodError in our own
    # code, and both landed in the same `errors` array — so an operator reading
    # `errors=39` could not tell "39 files have an upstream schema gap" from "39
    # files hit a bug in SPARC". An unexpected class now raises and fails the
    # run, which is the honest outcome for a bug in ours.
    #
    # Safe to rescue at this level: the per-candidate work runs inside
    # `write_through_parser`'s own transaction (#939), so a failure has already
    # rolled back cleanly, and this loop is not itself inside a transaction.
    rescue DocumentParseError,
           CdefMutationService::ValidationError,
           JSON::ParserError,
           ActiveRecord::RecordInvalid => e
      @logger.error("[AwsLabsCdefImportService] Failed to import #{candidate[:path]}: #{e.class} #{e.message}")
      errors << { path: candidate[:path], error: "#{e.class}: #{e.message}" }
    end

    errors = @fetch_errors + errors
    report_errors(errors)

    Result.new(discovered: tree_entries.length,
               imported: imported,
               skipped_unchanged: skipped_unchanged,
               superseded: superseded,
               errors: errors)
  end

  # #939 — a partial import used to be indistinguishable from a clean one.
  #
  # The count was reported alongside otherwise successful-looking totals and the
  # bodies were never logged, so a cold pass that failed a fifth of the corpus
  # read as a success and could not be diagnosed without reproducing it. That is
  # the first thing the issue asked for, and it is what tells an operator to
  # press "Refresh from AWS Labs" again — which, now that a failed file leaves no
  # row behind, is enough to complete the corpus.
  #
  # Distinct error CLASSES with counts, not 39 near-identical lines: the class is
  # what distinguishes an upstream schema gap from a transient fetch failure from
  # a bug in SPARC, and it is the thing worth putting in an issue.
  def report_errors(errors)
    return if errors.empty?

    by_class = errors.group_by { |e| e[:error].to_s.split(":").first }
                     .transform_values(&:length)
                     .sort_by { |_klass, count| -count }

    @logger.error(
      "[AwsLabsCdefImportService] Completed with #{errors.length} failed file(s). " \
      "By error class: #{by_class.map { |k, v| "#{k}=#{v}" }.join(' ')}. " \
      "Paths: #{errors.first(10).map { |e| e[:path] }.join(', ')}" \
      "#{errors.length > 10 ? " (+#{errors.length - 10} more)" : ''}"
    )

    AuditEvent.log(
      action: "aws_labs_cdef_refresh_degraded",
      metadata: {
        failed_files: errors.length,
        by_error_class: by_class.to_h,
        paths: errors.first(25).map { |e| e[:path] }
      }
    )
  rescue StandardError => e
    # Reporting must never be the reason an otherwise-complete import fails.
    @logger.warn("[AwsLabsCdefImportService] Could not record degraded-run report: #{e.class}: #{e.message}")
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
      next nil if meta[OSCAL_VERSION].blank?
      next nil if @allowed_oscal_versions.any? && !@allowed_oscal_versions.include?(meta[OSCAL_VERSION])

      {
        path: file[:path],
        sha: file[:sha],
        html_url: file[:html_url],
        content: file[:content],
        oscal_version: meta[OSCAL_VERSION],
        metadata_version: meta["version"].to_s,
        service_dir: service_dir_for(file[:path]),
        # Detected from content, not from the filename: the ordering below
        # depends on it, and `aws_regions.oscal.json` is a naming convention
        # upstream can change without telling anyone.
        defines_regions: defines_regions?(data)
      }
    rescue JSON::ParserError => e
      @logger.warn("[AwsLabsCdefImportService] Skipping #{entry['path']}: invalid JSON (#{e.message})")
      @fetch_errors << { path: entry["path"], error: "JSON::ParserError: #{e.message}" }
      nil
    # #939 — one file's fetch must not lose the other 229.
    #
    # Only JSON::ParserError was rescued here, so a rate limit or a read timeout
    # on a single blob raised straight out of `run` and abandoned the entire
    # pass — 230 files discarded because one request failed. This is the site
    # where transient network failure actually happens: the per-candidate import
    # loop below does no network I/O at all (the content is already in hand),
    # which is why the "GitHub is rate-limiting us" reading of the original
    # report did not survive measurement.
    #
    # The rescued list is deliberately explicit rather than a bare `rescue =>`.
    # An unexpected error class is a bug in SPARC, and it should raise rather
    # than be absorbed into a per-file error count that reads like a problem
    # with someone else's repository. See #968.
    rescue AwsLabsCdefSourceClient::Error,
           Net::OpenTimeout, Net::ReadTimeout,
           Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
           OpenSSL::SSL::SSLError => e
      @logger.warn("[AwsLabsCdefImportService] Fetch failed for #{entry['path']}: #{e.class}: #{e.message}")
      @fetch_errors << { path: entry["path"], error: "#{e.class}: #{e.message}" }
      nil
    end.compact

    fetched.group_by { |c| [ c[:service_dir], c[:oscal_version] ] }
           .map { |_, group| highest_version(group) }
  end

  def service_dir_for(path) = self.class.service_key_for_path(path)

  # True when this document defines the region components other CDEFs point at.
  def defines_regions?(data)
    Array(data.dig("component-definition", "components")).any? { |c| c["type"] == "region" }
  end

  # Import the regions CDEF before anything that references it.
  #
  # CdefComponentIndexer resolves a service's regions by looking up region
  # components ACROSS documents (`region_map` reads
  # `CdefComponent.where(component_type: "region")`), so a service indexed
  # before the regions CDEF exists resolves nothing and is stored with zero
  # regions. Nothing re-indexes it afterwards, so it stays that way until the
  # next time that particular document changes upstream.
  #
  # The indexer's own comment states the requirement — "the regions CDEF must be
  # indexed before the services that reference it" — but nothing enforced it,
  # and the import order is upstream's tree order. Alphabetically
  # `component-definitions/acm/…` sorts BEFORE
  # `component-definitions/aws_regions.oscal.json`, so the bug was partial and
  # silent: services early in the alphabet lost their regions, later ones kept
  # theirs, and the result looked like real data either way.
  #
  # `sort_by` with a boolean key is a stable partition — relative order within
  # each group is preserved, so this changes nothing except moving regions to
  # the front.
  def regions_first(candidates)
    candidates.sort_by { |candidate| candidate[:defines_regions] ? 0 : 1 }
  end

  # Re-index a document that was imported before the regions CDEF existed.
  #
  # Ordering fixes this going forward, but it does nothing for rows already in
  # the database: an unchanged file is skipped, so a service imported into an
  # instance with no regions CDEF keeps its empty `region_ids` until upstream
  # happens to edit that one file. On a weekly refresh that could be never.
  #
  # The content is already in hand — build_candidates fetched it to read the
  # metadata — so repairing costs no extra request. The indexer is idempotent by
  # design ("same input, same rows"), which is what makes re-running safe.
  #
  # Deliberately narrow: only when region components now exist AND this document
  # resolved none. A service that genuinely has no regions re-indexes on each
  # run, which is bounded work and self-correcting; a service that HAS regions
  # is left alone entirely.
  def repair_regions(document, candidate)
    return if candidate[:defines_regions]
    return unless CdefComponent.where(component_type: "region").exists?
    return if document.cdef_components.where.not(region_ids: []).exists?

    reindex_components(document, candidate[:content])
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
      repair_regions(existing, candidate)
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
  #
  # #939 — the whole sequence is ONE transaction, because the row was created
  # before the work that can fail.
  #
  # `CdefJsonParserService#parse` opens its own transaction (via
  # `CdefMutationService.apply`) and rolls back cleanly on failure — but the
  # `create!` above it did not, so a parse failure rolled back the children and
  # left the shell behind: `status: "processing"`, zero controls, and crucially
  # no `source_type`, which put it outside `CdefDocument.aws_labs_sourced`. That
  # made it invisible to the dedupe in `import_one`, so the next refresh could
  # not reuse or repair it and leaked a fresh one instead. 82 were measured on
  # one instance after four passes. They sorted to the top of the CDEF index and
  # broke OSCAL export, because a CDEF with no controls fails validation.
  #
  # Wrapping the create makes a failed import leave nothing at all, which is
  # what makes the existing "Refresh from AWS Labs" button sufficient to repair
  # a partial run: a file that failed has no row, so the dedupe finds no match
  # and simply imports it on the next pass. A killed process is covered by the
  # same mechanism — an uncommitted transaction dies with the connection.
  def write_through_parser(candidate, commit_sha:)
    ActiveRecord::Base.transaction do
      write_through_parser_inner(candidate, commit_sha: commit_sha)
    end
  end

  def write_through_parser_inner(candidate, commit_sha:)
    document = CdefDocument.create!(
      name: derive_name(candidate),
      status: "processing",
      cdef_type: "custom",
      file_type: "json",
      lifecycle_status: "published",
      globally_available: true,
      # #584 — must be an ISO 8601 datetime (OSCAL metadata.published
      # schema), not a boolean-string. The legacy "true" value tripped
      # the exporter validation.
      published: Time.current.iso8601
    )

    Tempfile.create([ "aws-labs-cdef-", ".json" ]) do |tmp|
      tmp.binmode
      tmp.write(candidate[:content])
      tmp.flush
      # #584 — AWS Labs OSCAL is run through the same pre-commit
      # validation as user uploads. The original validate: false
      # opt-out (#498 slice 3) turned out to be masking a bad test
      # fixture (one placeholder party UUID), not a real upstream
      # gap. A future real-world AWS Labs ingestion failure now
      # surfaces as an error in the import Result (not silently
      # ingested) so operators can file an issue with specifics.
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

    # #887 — the parser already indexed this document's components, but it ran
    # BEFORE enrichment, so `enriched_control_ids` (and the capabilities derived
    # from them) were empty at that point. Re-index now that the NIST mappings
    # exist. The indexer replaces a document's rows rather than merging, so
    # running it twice is exactly as correct as running it once.
    reindex_components(document, candidate[:content])

    document
  end

  # Best-effort: a document whose component index fails is still a usable
  # import, so this deliberately swallows rather than failing the file.
  #
  # #939 — the `requires_new: true` SAVEPOINT is load-bearing now that the
  # caller runs inside a transaction. This is the #963 shape exactly: rescuing a
  # database error inside a Postgres transaction WITHOUT a savepoint leaves the
  # transaction poisoned, so every later statement fails with an error naming
  # neither the original record nor the real cause. In #963 one colliding UUID
  # discarded an entire OSCAL import that way. The savepoint confines the
  # rollback to the indexer, so swallowing here stays a local decision instead
  # of silently destroying the import that contains it. See #968 for the audit
  # of this pattern elsewhere.
  def reindex_components(document, content)
    ActiveRecord::Base.transaction(requires_new: true) do
      CdefComponentIndexer.new(document, content).index!
    end
  rescue StandardError => e
    @logger.warn("[AwsLabsCdefImportService] reindex failed for #{document.id}: #{e.class}: #{e.message}")
  end

  # Issue #491 / #494 -- Two-hop NIST enrichment.
  #
  # For each AWS Security Hub control_id on a freshly-parsed CdefControl:
  #
  #   1. Direct lookup in the aws_security_hub_to_nist Converter
  #      (sourced from AWS Security Hub User Guide).
  #      Found  -> use those NIST ids; mark source = "aws_direct".
  #      Empty  -> proceed to step 2.
  #
  #   2. Pull the aws_config_rule for this SecHub id from the
  #      lib/data_mappings/aws_security_hub_to_nist.json bridge file
  #      (cached in memory).
  #      None recorded -> leave unmapped.
  #
  #   3. Lookup that Config Rule in the aws_config_to_nist Converter
  #      (sourced from mitre/heimdall2, hand-extensible).
  #      Found  -> use those NIST ids; mark source = "via_config_rule".
  #      Empty  -> leave unmapped.
  #
  # #912 — the AWS upstream identifier is never lost, but it no longer lives in
  # `control_id`. It moves to `source_control_id` (verbatim, never rewritten)
  # and `control_id` carries the NIST reference the converter resolved, or NULL
  # where it resolved nothing. Before the split both meanings shared one column,
  # so a Security Hub id was indistinguishable from a NIST control at every
  # consumer — and canonicalisation had to be disabled on the whole model to
  # avoid rewriting `IAM.3` to `iam.3`.
  #
  # The enrichment FIELDS below are unchanged: they remain the audit trail of
  # how the mapping was derived.
  #
  # Fields written per enriched CdefControl:
  #   - aws_security_hub_id   : the original SecHub identifier
  #   - nist_oscal_ids        : comma-joined OSCAL ids (sorted)
  #   - nist_primary_id       : lowest-sorted NIST id (grouping key)
  #   - nist_mapping_source   : "aws_direct" | "via_config_rule"
  #   - aws_config_rule       : the Config Rule name (when via_config_rule)
  def enrich_with_nist_mappings!(document)
    sec_hub_converter    = Converter.find_by(converter_type: "aws_security_hub_to_nist")
    aws_config_converter = Converter.find_by(converter_type: "aws_config_to_nist")

    unless sec_hub_converter
      @logger.debug("[AwsLabsCdefImportService] No aws_security_hub_to_nist Converter; skipping NIST enrichment")
      return
    end

    bridge = sec_hub_config_rule_bridge

    enriched_count = 0
    document.cdef_controls.find_each do |control|
      # #912 — the Security Hub id is the SOURCE identifier. Read it from
      # `source_control_id` where the split has already been applied, and fall
      # back to `control_id` for rows the deferred backfill has not reached yet.
      sec_hub_id = control.source_identifier.to_s.presence || control.control_id.to_s
      next unless sec_hub_id.match?(/\A[A-Za-z][A-Za-z0-9]*\.\d+\z/)

      # #912 — clear the Security Hub id out of `control_id` before attempting
      # resolution. If the converter maps it, `write_enrichment!` writes the NIST
      # reference back; if it does not, the row is correctly left with no control
      # identifier and is reported as unmapped rather than presenting a Security
      # Hub id as though it were a NIST control.
      record_aws_source!(control, sec_hub_id)
      # Compare canonically: `control_id` is canonicalised on write now, so the
      # stored value is `iam.99999` while the source is `IAM.99999`. Comparing
      # raw never matched, and the Security Hub id stayed in the NIST column.
      if control.control_id.present? && control.control_id == ControlId.canonical(sec_hub_id)
        control.update_columns(control_id: nil)
      end

      direct_ids = sec_hub_converter.converter_entries
        .where(source_id: sec_hub_id)
        .reorder(nil).distinct.pluck(:target_id).uniq.sort

      if direct_ids.any?
        write_enrichment!(control, sec_hub_id, direct_ids, source: "aws_direct")
        enriched_count += 1
        next
      end

      # Fallback: chain through AWS Config Rule.
      config_rule = bridge[sec_hub_id]
      next if config_rule.nil? || config_rule.empty? || aws_config_converter.nil?

      chained_ids = aws_config_converter.converter_entries
        .where(source_id: config_rule)
        .reorder(nil).distinct.pluck(:target_id).uniq.sort

      next if chained_ids.empty?

      write_enrichment!(control, sec_hub_id, chained_ids, source: "via_config_rule", config_rule: config_rule)
      enriched_count += 1
    end

    if enriched_count > 0
      @logger.info("[AwsLabsCdefImportService] Enriched #{enriched_count} controls with NIST mappings " \
                   "for document #{document.id} (#{document.name})")
    end
  end

  # Provenance first, for every AWS control — mapped or not. An unmapped
  # Security Hub control must still say where it came from.
  def record_aws_source!(control, sec_hub_id)
    return if control.source_control_id == sec_hub_id && control.source_vocabulary == "aws_security_hub"

    control.update_columns(source_control_id: sec_hub_id, source_vocabulary: "aws_security_hub")
  end

  def write_enrichment!(control, sec_hub_id, nist_ids, source:, config_rule: nil)
    # #912 — `control_id` now holds the NIST reference. `update_columns` skips
    # validations deliberately: a control invalid for an unrelated reason must
    # still receive its resolved mapping.
    control.update_columns(control_id: ControlId.canonical(nist_ids.first))

    upsert_cdef_field!(control, "aws_security_hub_id", sec_hub_id, editable: false)
    upsert_cdef_field!(control, "nist_oscal_ids", nist_ids.join(","), editable: false)
    upsert_cdef_field!(control, "nist_primary_id", nist_ids.first, editable: false)
    upsert_cdef_field!(control, "nist_mapping_source", source, editable: false)
    upsert_cdef_field!(control, "aws_config_rule", config_rule, editable: false) if config_rule
  end

  def upsert_cdef_field!(control, field_name, field_value, editable:)
    field = control.cdef_control_fields.find_or_initialize_by(field_name: field_name)
    field.update!(field_value: field_value, editable: editable)
  end

  # Cached SecHub -> AWS Config Rule bridge, built once per service
  # instance from the scraped JSON. Used as the second hop when the
  # AWS Security Hub converter has no direct row for a SecHub id.
  def sec_hub_config_rule_bridge
    @sec_hub_config_rule_bridge ||= begin
      require Rails.root.join("lib/aws_security_hub/aws_security_hub_mapping_loader")
      path = Rails.root.join("lib/data_mappings/aws_security_hub_to_nist.json")
      if path.exist?
        AwsSecurityHub::AwsSecurityHubMappingLoader.build_config_rule_bridge(JSON.parse(File.read(path)))
      else
        {}
      end
    end
  end

  def derive_name(candidate)
    # component-definitions/s3/s3-cd.json → "AWS s3 (oscal 1.1.2)"
    "AWS #{candidate[:service_dir]} (oscal #{candidate[:oscal_version]})"
  end
end
