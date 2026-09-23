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
      ordered_links(links).each do |link|
        records << build_record(attestation, link)
      end
    end
    records
  end

  def to_json(*args)
    JSON.generate(call, *args)
  end

  private

  # ORDER THE DENORMALIZED RECORDS (#1177).
  #
  # `find_each` orders the attestations by primary key, but the links carried
  # no order at all — not on the association, not in the query — so the preload
  # returned them in physical row order, which shifts as the table accumulates
  # and reclaims rows. This is a DELIVERED ARTEFACT, not an internal view: an
  # export whose record order varies between runs cannot be diffed against a
  # previous delivery or checksummed, and produces spurious changes in whatever
  # stores it downstream.
  #
  # Sorted on `ControlId.padded`, which is the form this codebase already
  # designates for display and sorting, because it zero-pads and therefore
  # orders naturally. A plain sort is deterministic but wrong for a reader:
  #
  #   plain:   ac-10, ac-2, ac-2.1, ac-3, au-6
  #   padded:  ac-2,  ac-2.1, ac-3, ac-10, au-6
  #
  # `id` is the tie-break so two links on one control cannot swap either.
  def ordered_links(links)
    links.sort_by { |link| [ ControlId.padded(link.control_id), link.id.to_i ] }
  end

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
