# Emits SPARC attestation records in the CMS / SAF CLI attestation
# JSON schema (https://saf.mitre.org/) used by InSpec / Heimdall / OSCAL
# emitters. See issue #440.
#
# Schema (per record):
#   - control_id : identifier matching the upstream control
#   - explanation: reviewer narrative + evidence reference
#   - frequency  : cadence keyword
#   - status     : "passed" | "failed"
#   - updated    : ISO-8601 date
#   - updated_by : reviewer name + role
#
# SPARC's `Attestation` is linked to an `Evidence`, which is linked to
# 0..N controls via `evidence_control_links`. The CMS schema is one
# attestation record per control_id, so this service denormalizes:
# an attestation tied to evidence with N control links emits N records
# (one per control_id). Attestations without any control link emit zero
# records — the CMS shape is meaningless without a control_id.
class CmsAttestationExportService
  DEFAULT_FREQUENCY = "ad_hoc".freeze

  def initialize(scope = Attestation.all)
    @scope = scope
  end

  def call
    records = []
    @scope.includes(evidence: :evidence_control_links).find_each do |attestation|
      links = attestation.evidence&.evidence_control_links || []
      links.each do |link|
        records << build_record(attestation, link)
      end
    end
    records
  end

  def to_json(*args)
    JSON.generate(call, *args)
  end

  private

  def build_record(attestation, link)
    {
      # #911 — RENDERED, not passed through. Control identifiers are stored
      # canonically (`ca-7`) so internal comparisons stop failing silently, but
      # this payload is an external contract: the CMS / SAF CLI attestation
      # schema consumed downstream by Heimdall, which keys on the NIST tag.
      # Leaking the storage form would silently change every delivered record
      # from `CA-7` to `ca-7`.
      #
      # An export renders the form its consumer's schema requires. It does not
      # publish SPARC's storage convention. (CCI is a separate tag with its own
      # helpers on the Heimdall side, and is deliberately untouched by
      # ControlId's padding rules — see ControlId::MAX_PADDED_DIGITS.)
      control_id: ControlId.nist_tag(link.control_id),
      explanation: attestation.statement,
      frequency: attestation.frequency || DEFAULT_FREQUENCY,
      status: attestation.status,
      updated: attestation.attested_at.utc.iso8601,
      updated_by: format_updated_by(attestation)
    }
  end

  def format_updated_by(attestation)
    role = attestation.role.present? ? " (#{attestation.role_label})" : ""
    "#{attestation.attester_name}#{role}"
  end
end
