# frozen_string_literal: true

require "json"
require "digest"
require "stringio"

# #447 — translation IN. Parse an uploaded HDF results document (single scan or a
# `saf convert` bundle — a top-level array of HDF docs) into persisted ScanRun +
# ScannerFinding records, scoped to an AuthorizationBoundary.
#
# #1354 — HDF v2 AND v3. Every document is validated by the pinned `hdf` CLI
# (hdf-libs) before anything is read from it. A legacy v2 document (InSpec
# exec-json, `profiles[]`) is validated against the v2 schema and converted up
# with `hdf convert --from hdf@2 --to hdf@3`; a v3 document is validated against
# the v3 results schema. There is then ONE parser, for v3 `baselines[]`.
# Converting up rather than down means a v3 producer loses nothing, and the CLI
# — not SPARC's reading of the shape — is the proof a document conforms.
#
# Idempotent by (boundary, control_id): a fresh scan UPDATES the current finding
# and repoints it to the new ScanRun rather than duplicating, so the disposition
# attached to that (boundary, control_id) survives re-ingest.
#
# HDF is JSON (not XML), so the input guard here is a byte-size cap + strict JSON
# parse + schema validation by the hdf CLI — there is no XXE/entity surface as
# with the XML upload paths (which route through XmlSecurity).
#
# NIST 800-53: CA-7 (continuous monitoring), RA-5 (vulnerability scanning),
# SI-10 (input validation — size cap, strict parse, schema validation by the
# CLI, bounded CLI output), SI-7 (integrity — raw_hdf_digest is the SHA-256 of
# the bytes as uploaded, never of the converted document).
class HdfIngestService
  class IngestError < StandardError; end

  # #1354 — seconds one `hdf` call may run before it is killed. Validating or
  # converting a document at the upload cap takes seconds; this bounds a wedged
  # binary, not a slow one.
  HDF_TIMEOUT_SECONDS = 120

  # Longest hdf message carried into an IngestError (it reaches the UI flash and
  # the API error envelope).
  MAX_HDF_MESSAGE = 500

  # The tempfile names HdfRunner gives the upload, which hdf echoes back in its
  # messages. They are replaced with "the upload" before a message is shown.
  HDF_TEMPFILE_PATH = %r{\S*hdf-(?:input|v3)-\S*?\.json}

  # HDF control `impact` (0.0–1.0) → severity, matching the Heimdall convention.
  def self.severity_from_impact(impact)
    case impact.to_f
    when 0.9..Float::INFINITY then "CRITICAL"
    when 0.7...0.9 then "HIGH"
    when 0.4...0.7 then "MEDIUM"
    when 0.1...0.4 then "LOW"
    else "INFORMATIONAL"
    end
  end

  # A v3 requirement's status as ingest stores it (see #status_for, which
  # explains the order). Shared with ExchangeDelta, so a delta classes a
  # requirement exactly as ingest stores it (#1354).
  def self.requirement_status(req)
    statuses = Array(req["results"]).filter_map { |r| r["status"].to_s.presence if r.is_a?(Hash) }
    return "failed" if statuses.include?("failed")
    return "passed" if statuses.include?("passed")
    return "error" if statuses.include?("error")
    return "notApplicable" if statuses.include?("notApplicable")
    return "skipped" if statuses.any?

    "notApplicable"
  end

  # @param runner [HdfRunner, nil] injected for specs; defaults to the pinned
  #   CLI with a timeout.
  def initialize(authorization_boundary, runner: nil)
    @boundary = authorization_boundary
    @runner = runner || HdfRunner.new(timeout: HDF_TIMEOUT_SECONDS)
  end

  # @param content [String] raw HDF JSON bytes (v2 or v3)
  # @param cdef_document [CdefDocument, nil] the target/CDEF the scan ran against (#811)
  # @param scanner_scope [String] "target" (CDEF-specific) or "boundary" (e.g. AWS Config)
  # @param attach_file [Boolean] persist the original scan content as a durable artefact
  # @return [ScanRun]
  def ingest(content, source_filename: nil, created_by: nil, scanner_hint: nil,
             cdef_document: nil, scanner_scope: "target", attach_file: true)
    raw = content.to_s
    raise IngestError, "Empty file" if raw.strip.empty?

    max = SparcConfig.max_upload_bytes
    raise IngestError, "File exceeds the #{max}-byte upload limit" if raw.bytesize > max

    docs = parse(raw).map { |doc, bytes| to_v3(doc, bytes, max) }
    controls = docs.flat_map { |doc| controls_from(doc, scanner_hint) }
    raise IngestError, "No HDF controls found in the uploaded document" if controls.empty?

    scanner = scanner_hint.presence ||
              docs.filter_map { |d| scanner_name(d) }.first ||
              "unknown"

    ScanRun.transaction do
      run = ScanRun.create!(
        authorization_boundary: @boundary,
        cdef_document: cdef_document,
        scanner_scope: ScanRun::SCANNER_SCOPES.include?(scanner_scope.to_s) ? scanner_scope.to_s : "target",
        scanner: scanner,
        scanner_version: docs.filter_map { |d| d.dig("baselines", 0, "version") }.first,
        ingested_at: Time.current,
        source_filename: source_filename,
        # SI-7 — the digest and the attached file are the ORIGINAL upload, so a
        # v2 file converted up still matches the bytes its producer wrote.
        raw_hdf_digest: Digest::SHA256.hexdigest(raw),
        created_by: created_by
      )
      # #811 — persist the original scan content as a durable artefact.
      if attach_file
        run.file.attach(io: StringIO.new(raw),
                        filename: source_filename.presence || "scan.hdf.json",
                        content_type: "application/json")
      end
      controls.each { |c| record_finding(run, c) }
      run.update!(
        finding_count: controls.size,
        passed_count:  controls.count { |c| c[:status] == "passed" },
        failed_count:  controls.count { |c| c[:status] == "failed" },
        skipped_count: controls.count { |c| c[:status] == "skipped" }
      )
      run
    end
  end

  private

  # [[doc, bytes], ...] — one entry per HDF document. A single document keeps
  # the uploaded bytes, so hdf's error lines point into the user's own file.
  def parse(raw)
    data = JSON.parse(raw)
    case data
    when Hash then [ [ data, raw ] ]
    when Array
      data.map do |doc|
        raise IngestError, "Unrecognized HDF structure — every bundle entry must be an HDF object" unless doc.is_a?(Hash)

        [ doc, JSON.generate(doc) ]
      end
    else raise IngestError, "Unrecognized HDF structure — expected an object or array"
    end
  rescue JSON::ParserError => e
    raise IngestError, "Invalid HDF JSON: #{e.message.to_s.truncate(120)}"
  end

  # HDF v2 is the legacy InSpec exec-json shape: a `profiles[]` array. Anything
  # else is read as v3 and must satisfy the v3 results schema.
  def legacy_v2?(doc)
    doc["profiles"].is_a?(Array)
  end

  # SI-10 — validate with the pinned CLI, then return the v3 document: the input
  # itself when it is v3, its `hdf convert --from hdf@2` upgrade when it is v2.
  def to_v3(doc, bytes, max_bytes)
    if legacy_v2?(doc)
      hdf!("validation") { @runner.validate(StringIO.new(bytes), type: "results", schema_ver: 2) }
      hdf!("conversion") { @runner.convert_legacy_hdf(StringIO.new(bytes), max_output_bytes: max_bytes) }
    else
      hdf!("validation") { @runner.validate(StringIO.new(bytes), type: "results") }
      doc
    end
  end

  # Every way the CLI can fail becomes an IngestError, which both controllers
  # already render: a missing binary, a timeout, or a non-zero exit (hdf's own
  # message, bounded, with the tempfile path it names replaced).
  def hdf!(step)
    yield
  rescue HdfRunner::Error => e
    raise IngestError, "HDF #{step} failed: #{hdf_message(e)}"
  rescue SystemCallError => e
    raise IngestError, "HDF #{step} could not run: the hdf CLI is not available (#{e.class.name.demodulize})"
  end

  def hdf_message(error)
    text = error.stderr.to_s.strip.presence || error.message.to_s
    text.gsub(HDF_TEMPFILE_PATH, "the upload").squish.truncate(MAX_HDF_MESSAGE)
  end

  def scanner_name(doc)
    doc.dig("baselines", 0, "name").presence || doc.dig("components", 0, "name").presence
  end

  # One finding per v3 requirement (`baselines[].requirements[]`). raw_hdf is
  # the requirement as v3 carries it — for a v2 upload, its converted form.
  def controls_from(doc, scanner_hint)
    scanner = scanner_hint.presence || scanner_name(doc)
    Array(doc["baselines"]).flat_map do |baseline|
      next [] unless baseline.is_a?(Hash)

      Array(baseline["requirements"]).filter_map do |req|
        next unless req.is_a?(Hash)

        cid = req["id"].to_s.strip
        next if cid.blank?

        {
          control_id:      cid,
          title:           req["title"].to_s,
          description:     default_description(req),
          severity:        severity_for(req),
          status:          status_for(req),
          scanner:         scanner,
          component_ref:   component_ref_for(req),
          source_location: source_location_for(req),
          raw_hdf:         req
        }
      end
    end
  end

  # v3 carries descriptions as labelled entries and requires a `default` one,
  # which is what a v2 control's `desc` converts to.
  def default_description(req)
    entry = Array(req["descriptions"]).find { |d| d.is_a?(Hash) && d["label"] == "default" }
    entry ? entry["data"].to_s : ""
  end

  # HDF tag keys that can carry component identity, in preference order.
  COMPONENT_REF_TAGS = %w[component purl package image_digest package_name].freeze

  # #811 — component identity (purl / image digest / hostname) from HDF tags.
  def component_ref_for(req)
    tags = req["tags"].is_a?(Hash) ? req["tags"] : {}
    key = COMPONENT_REF_TAGS.find { |k| tags[k].present? }
    tags[key].to_s if key
  end

  # #811 — the source file / location the finding points at.
  def source_location_for(req)
    loc = req["sourceLocation"]
    return loc["ref"].to_s.presence || loc.to_json if loc.is_a?(Hash)

    Array(req["results"]).filter_map { |r| r["codeDesc"] if r.is_a?(Hash) }.first
  end

  # tags.severity when it is one of SPARC's severities, else the impact band.
  # The requirement's own `severity` field is not read: hdf derives it from
  # impact on bands that differ from SPARC's below 0.1, and reading it would
  # change what a v2 file stores.
  def severity_for(req)
    tag = req.dig("tags", "severity").to_s.upcase
    return tag if ScannerFinding::SEVERITIES.include?(tag)

    self.class.severity_from_impact(req["impact"])
  end

  # Aggregate the requirement's per-result statuses to a single finding status.
  #
  # Read from results[], not `effectiveStatus`: effectiveStatus applies any
  # statusOverrides the document carries, and SPARC keeps its own dispositions
  # (FindingDisposition) — the finding is what the scan assessed.
  #
  # #1368 — as of hdf-cli 3.8.0 an impact of 0 no longer means notApplicable:
  # the results decide. `hdf convert --from hdf@2` keeps InSpec's convention —
  # a control scored 0 whose results are all skipped gains a notApplicable
  # result — so that case arrives here as notApplicable. v3 has no `skipped`:
  # v2's skipped converts to `notReviewed`, which SPARC stores as "skipped".
  # The order (failed, passed, error, notApplicable, notReviewed) is SPARC's
  # historical one, so a v2 file stores what it stored before #1354.
  def status_for(req) = self.class.requirement_status(req)

  # #811 — record a per-scan_run finding, demoting the prior current finding to
  # history and computing the re-occurrence lifecycle vs the prior state + its
  # disposition (carry-forward / re_failed / expired / new). History is retained.
  def record_finding(run, attrs)
    prior = ScannerFinding.current.find_by(
      authorization_boundary_id: @boundary.id, control_id: attrs[:control_id]
    )
    disposition = FindingDisposition.find_by(
      authorization_boundary_id: @boundary.id, control_id: attrs[:control_id]
    )
    lifecycle = lifecycle_for(prior, disposition, attrs)

    prior&.update!(current: false, lifecycle_status: "superseded")

    ScannerFinding.create!(
      scan_run: run, authorization_boundary: @boundary, cdef_document: run.cdef_document,
      control_id: attrs[:control_id], status: attrs[:status], severity: attrs[:severity],
      title: attrs[:title], description: attrs[:description], scanner: attrs[:scanner],
      component_ref: attrs[:component_ref], source_location: attrs[:source_location],
      raw_hdf: attrs[:raw_hdf], current: true, lifecycle_status: lifecycle
    )
  end

  SEVERITY_RANK = { "CRITICAL" => 0, "HIGH" => 1, "MEDIUM" => 2, "LOW" => 3, "INFORMATIONAL" => 4 }.freeze

  def lifecycle_for(prior, disposition, attrs)
    return "new" if prior.nil?

    if disposition
      return "expired" if disposition.expired?

      if attrs[:status] == "failed"
        return "re_failed" if prior.status != "failed" ||
                              severity_worsened?(attrs[:severity], prior.severity) ||
                              prior.component_ref != attrs[:component_ref]

        return "carried_forward"
      end
    end
    "new"
  end

  def severity_worsened?(new_sev, old_sev)
    new_rank = SEVERITY_RANK[new_sev.to_s.upcase]
    old_rank = SEVERITY_RANK[old_sev.to_s.upcase]
    return false if new_rank.nil? || old_rank.nil?

    new_rank < old_rank
  end
end
