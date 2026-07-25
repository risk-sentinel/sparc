# frozen_string_literal: true

require "json"
require "digest"

# #447 — translation IN. Parse an uploaded HDF results document (single scan or a
# `saf convert` bundle — a top-level array of HDF docs) into persisted ScanRun +
# ScannerFinding records, scoped to an AuthorizationBoundary.
#
# Idempotent by (boundary, control_id): a fresh scan UPDATES the current finding
# and repoints it to the new ScanRun rather than duplicating, so the disposition
# attached to that (boundary, control_id) survives re-ingest.
#
# HDF is JSON (not XML), so the input guard here is a byte-size cap + strict JSON
# parse + structural shape check — there is no XXE/entity surface as with the XML
# upload paths (which route through XmlSecurity).
#
# NIST 800-53: CA-7 (continuous monitoring), RA-5 (vulnerability scanning),
# SI-10 (input validation — size cap + shape guard).
class HdfIngestService
  class IngestError < StandardError; end

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

  def initialize(authorization_boundary)
    @boundary = authorization_boundary
  end

  # @param content [String] raw HDF JSON bytes
  # @return [ScanRun]
  def ingest(content, source_filename: nil, created_by: nil, scanner_hint: nil)
    raw = content.to_s
    raise IngestError, "Empty file" if raw.strip.empty?

    max = SparcConfig.max_upload_bytes
    raise IngestError, "File exceeds the #{max}-byte upload limit" if raw.bytesize > max

    docs = parse(raw)
    controls = docs.flat_map { |doc| controls_from(doc, scanner_hint) }
    raise IngestError, "No HDF controls found in the uploaded document" if controls.empty?

    scanner = scanner_hint.presence ||
              docs.filter_map { |d| scanner_name(d) }.first ||
              "unknown"

    ScanRun.transaction do
      run = ScanRun.create!(
        authorization_boundary: @boundary,
        scanner: scanner,
        scanner_version: docs.filter_map { |d| d.dig("profiles", 0, "version") }.first,
        ingested_at: Time.current,
        source_filename: source_filename,
        raw_hdf_digest: Digest::SHA256.hexdigest(raw),
        created_by: created_by
      )
      controls.each { |c| upsert_finding(run, c) }
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

  def parse(raw)
    data = JSON.parse(raw)
    case data
    when Array then data
    when Hash  then [ data ]
    else raise IngestError, "Unrecognized HDF structure — expected an object or array"
    end
  rescue JSON::ParserError => e
    raise IngestError, "Invalid HDF JSON: #{e.message.to_s.truncate(120)}"
  end

  def scanner_name(doc)
    return nil unless doc.is_a?(Hash)

    doc.dig("profiles", 0, "name").presence || doc.dig("platform", "name").presence
  end

  def controls_from(doc, scanner_hint)
    return [] unless doc.is_a?(Hash)

    scanner = scanner_hint.presence || scanner_name(doc)
    Array(doc["profiles"]).flat_map do |profile|
      Array(profile["controls"]).filter_map do |ctrl|
        next unless ctrl.is_a?(Hash)

        cid = ctrl["id"].to_s.strip
        next if cid.blank?

        {
          control_id:  cid,
          title:       ctrl["title"].to_s,
          description: ctrl["desc"].to_s,
          severity:    severity_for(ctrl),
          status:      status_for(ctrl),
          scanner:     scanner,
          raw_hdf:     ctrl
        }
      end
    end
  end

  def severity_for(ctrl)
    tag = ctrl.dig("tags", "severity").to_s.upcase
    return tag if ScannerFinding::SEVERITIES.include?(tag)

    self.class.severity_from_impact(ctrl["impact"])
  end

  # Aggregate the control's per-result statuses to a single HDF control status.
  def status_for(ctrl)
    statuses = Array(ctrl["results"]).filter_map { |r| r["status"].to_s.presence if r.is_a?(Hash) }
    return "failed" if statuses.include?("failed")
    return "notApplicable" if ctrl["impact"].to_f.zero?
    return "passed" if statuses.include?("passed")
    return "error" if statuses.include?("error")
    return "skipped" if statuses.any?

    "notApplicable"
  end

  def upsert_finding(run, attrs)
    finding = ScannerFinding.find_or_initialize_by(
      authorization_boundary_id: @boundary.id, control_id: attrs[:control_id]
    )
    finding.assign_attributes(
      scan_run: run,
      status:      attrs[:status],
      severity:    attrs[:severity],
      title:       attrs[:title],
      description: attrs[:description],
      scanner:     attrs[:scanner],
      raw_hdf:     attrs[:raw_hdf]
    )
    finding.save!
  end
end
