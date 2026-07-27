# frozen_string_literal: true

require "openssl"
require "base64"
require "json"

# #809 goal 2 — package a boundary's HDF Amendments + findings + dispositions into
# a single, signed bundle the consumer can archive or feed downstream. The bundle
# is HMAC-SHA256 signed with an instance key derived from SPARC_HASH
# (SparcKeyDerivation), so it is tamper-evident and provably from this SPARC
# instance — the same signing pattern as the federation bundles (#372).
#
# NIST 800-53: AU-10 (non-repudiation), CA-7 (continuous monitoring), SI-12.
class HdfPackageService
  SIGNING_PURPOSE = "hdf-package-signing-v1"

  def initialize(boundary)
    @boundary = boundary
  end

  # @return [Hash] { payload, encoded_payload, signature, algorithm }
  def build
    payload = {
      "format"       => "sparc-hdf-package/v1",
      "generated_by" => "SPARC #{SparcConfig.version}",
      "boundary"     => { "slug" => @boundary.slug, "uuid" => @boundary.uuid, "name" => @boundary.name },
      "amendments"   => HdfAmendmentExportService.new(@boundary).export(verify: false),
      "findings"     => findings_summary,
      "dispositions" => dispositions_summary
    }
    encoded = Base64.urlsafe_encode64(JSON.generate(payload))
    {
      "payload"         => payload,
      "encoded_payload" => encoded,
      "signature"       => sign(encoded),
      "algorithm"       => "HMAC-SHA256"
    }
  end

  private

  def findings_summary
    @boundary.scanner_findings.current.order(:control_id).map do |f|
      {
        "control_id" => f.control_id, "status" => f.status, "severity" => f.severity,
        "lifecycle_status" => f.lifecycle_status, "component_ref" => f.component_ref,
        "cdef_document_id" => f.cdef_document_id, "scanner" => f.scanner
      }
    end
  end

  def dispositions_summary
    @boundary.finding_dispositions.order(:control_id).map do |d|
      {
        "control_id" => d.control_id, "kind" => d.kind, "hdf_status" => d.hdf_status,
        "approval_status" => d.approval_status, "decided_by" => d.decided_by,
        "approved_by" => d.approved_by, "valid_until" => d.valid_until&.utc&.iso8601,
        "applicable" => d.applicable?, "signature_hash" => d.signature_hash
      }
    end
  end

  def sign(encoded)
    key = SparcKeyDerivation.derive(SIGNING_PURPOSE)
    OpenSSL::HMAC.hexdigest("SHA256", key, encoded)
  end
end
