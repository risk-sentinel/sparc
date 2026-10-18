# Bidirectional translation between HDF and OSCAL artefacts using the
# MITRE hdf-libs CLI. Stateless — does not persist anything to SPARC's
# database. Tenant compliance state remains in tenant systems.
#
# Used by `Api::V1::TranslationsController` (#449, #663) to expose
# translation endpoints:
#   - HDF results    → OSCAL SAR
#   - HDF results    → OSCAL POAM
#   - HDF Amendments → OSCAL POAM
#   - OSCAL POAM     → HDF Amendments
#
# All three flows are pure pass-through to `hdf convert`. SPARC's value
# is centralizing the binary install, version pinning, and surfacing the
# translation as authenticated REST endpoints.
class HdfOscalTranslationService
  OSCAL_POAM = "oscal-poam"
  BACK_MATTER = "back-matter".freeze

  def initialize(runner: HdfRunner.new)
    @runner = runner
  end

  # HDF results → OSCAL Assessment Results
  # @param hdf_input [String, IO] file path or IO of the HDF results JSON
  # @param boundary [AuthorizationBoundary, nil] optional — when provided,
  #   SPARC's existing Evidence records linked to the boundary are merged
  #   into the OSCAL `back-matter.resources[]` array
  # @return [Hash] OSCAL SAR document
  def hdf_to_oscal_sar(hdf_input, boundary: nil)
    oscal = @runner.convert(hdf_input, from: "hdf", to: "oscal-sar")
    validate_oscal!(:assessment_results, enrich_back_matter(oscal, boundary))
  end

  # HDF results → OSCAL Plan of Action and Milestones
  # @param hdf_input [String, IO]
  # @param boundary [AuthorizationBoundary, nil] optional back-matter enrichment
  # @return [Hash] OSCAL POAM document
  def hdf_to_oscal_poam(hdf_input, boundary: nil)
    oscal = @runner.convert(hdf_input, from: "hdf", to: OSCAL_POAM)
    validate_oscal!(:poam, enrich_back_matter(oscal, boundary))
  end

  # HDF Amendments → OSCAL Plan of Action and Milestones
  #
  # hdf-cli 3.2.0 removed the direct hdf→oscal-poam converter; the supported
  # path is now hdf-amendments→oscal-poam (#663). Pure pass-through to
  # `hdf convert --from hdf-amendments --to oscal-poam`.
  # @param amendments_input [String, IO] file path or IO of an HDF Amendments JSON
  # @param boundary [AuthorizationBoundary, nil] optional back-matter enrichment
  # @return [Hash] OSCAL POAM document
  def oscal_poam_from_hdf_amendments(amendments_input, boundary: nil)
    oscal = @runner.convert(amendments_input, from: "hdf-amendments", to: OSCAL_POAM)
    validate_oscal!(:poam, enrich_back_matter(oscal, boundary))
  end

  # The amendments document, plus the requirement ids of the overdue amendments
  # it reports on — left out of `amendments` unless the caller asked for them.
  AmendmentsResult = Struct.new(:amendments, :overdue_requirement_ids, :overdue_included, keyword_init: true)

  # #1208 — refused because of overdue amendments ALONE, so the caller can fix
  # it by asking for them (`include_overdue`). A subclass, so every existing
  # HdfRunner::Error handler still catches it.
  class OverdueAmendmentsError < HdfRunner::Error; end

  # OSCAL POAM → HDF Amendments
  #
  # #1208 — an overdue POA&M risk is ordinary input, not a reason to refuse the
  # whole document. hdf-cli 3.7.2 measured: `amend verify` fails on an expired
  # amendment with no flag to pass it, and `amend apply` refuses any document
  # that holds one. So, by default, the overdue amendments are LEFT OUT and
  # reported, and the document returned still applies cleanly — the same rule
  # HdfAmendmentExportService follows. `include_overdue: true` returns them
  # all, as a document `amend apply` will refuse (owner, option C).
  #
  # Structural faults are refused either way: a schema error, an invalid
  # override, or a broken chain is something wrong with the document, where an
  # expiry is only something true about it.
  #
  # `integrity.checksum` is the SHA-256 of the INPUT POA&M (measured), not of
  # the overrides, so leaving overrides out does not falsify it.
  #
  # NIST SP 800-53 Rev 5: SI-10 (input validation), CA-5 (POA&M), SI-2.
  # @param oscal_input [String, IO] file path or IO of an OSCAL POAM JSON/XML
  # @param include_overdue [Boolean] return overdue amendments too
  # @return [AmendmentsResult]
  def oscal_poam_to_hdf_amendments(oscal_input, include_overdue: false)
    amendments = @runner.convert(oscal_input, from: OSCAL_POAM)
    report = with_amendments_file(amendments) { |path| @runner.amend_verify_report(path) }
    refuse_structural_faults!(report)

    overdue, current = Array(amendments["overrides"]).partition { |o| overdue?(o) }
    unless overdue.size == report["expiredOverrides"].to_i
      raise HdfRunner::Error.new(
        "hdf amend verify counted #{report['expiredOverrides'].to_i} expired amendment(s); SPARC counted " \
        "#{overdue.size}. Refusing rather than guessing which to leave out.",
        command: "hdf amend verify --json", exit_code: 1, stderr: ""
      )
    end
    overdue_ids = overdue.map { |o| o["requirementId"] }

    if include_overdue || overdue.empty?
      return AmendmentsResult.new(amendments: amendments, overdue_requirement_ids: overdue_ids,
                                  overdue_included: overdue.any?)
    end

    if current.empty?
      raise OverdueAmendmentsError.new(
        "every amendment in this POA&M is overdue (#{overdue_ids.join(', ')}), so no amendments document " \
        "that `hdf amend apply` accepts can be produced. Pass include_overdue=true to receive them.",
        command: "hdf amend verify", exit_code: 1, stderr: ""
      )
    end

    filtered = amendments.merge("overrides" => current)
    begin
      with_amendments_file(filtered) { |path| @runner.amend_verify(path) }
    rescue HdfRunner::Error => e
      # Each amendment's checksum is recorded by the NEXT one on the same
      # requirement, so leaving an overdue one out can break the chain.
      raise OverdueAmendmentsError.new(
        "leaving out the overdue amendment(s) (#{overdue_ids.join(', ')}) leaves a document that does not " \
        "verify: #{e.message}. Pass include_overdue=true to receive the whole document.",
        command: e.command, exit_code: e.exit_code, stderr: e.stderr
      )
    end

    AmendmentsResult.new(amendments: filtered, overdue_requirement_ids: overdue_ids, overdue_included: false)
  end

  private

  def with_amendments_file(amendments)
    Tempfile.create([ "hdf-amendments-", ".json" ]) do |f|
      f.write(JSON.generate(amendments))
      f.flush
      yield f.path
    end
  end

  def refuse_structural_faults!(report)
    faults = Array(report["schemaErrors"])
    faults << "#{report['invalidOverrides']} invalid amendment(s)" if report["invalidOverrides"].to_i.positive?
    faults << "the amendment chain is broken" if report.dig("chain", "valid") == false
    return if faults.empty?

    raise HdfRunner::Error.new("verification failed: #{faults.join('; ')}",
                               command: "hdf amend verify --json", exit_code: 1, stderr: "")
  end

  # Past its expiresAt, as `amend verify` judges it. An override with no
  # expiresAt is a schema error, already refused above.
  def overdue?(override)
    Time.iso8601(override["expiresAt"].to_s) <= Time.current
  rescue ArgumentError
    false
  end

  # #831 — never hand back OSCAL that fails NIST's own schema.
  #
  # #1017 — and it means EVERY emitting path. #831 added this call to
  # `hdf_to_oscal_sar` and to neither POA&M-producing sibling, while the
  # controller's rescue block advertised the guarantee for all three. The gap
  # was reachable: `poam_from_amendments` returned a 200 carrying
  # `poam-items: null`, which SPARC's own validator rejects.
  #
  # Every other OSCAL-producing path in SPARC calls
  # `OscalSchemaValidationService.validate!` and refuses to emit an invalid
  # document. The translation endpoints were the exception: an API consumer
  # asked SPARC to translate HDF into an Assessment Results document, got a
  # 200, and received something no OSCAL tool would accept. A 200 carrying
  # invalid OSCAL is worse than an error, because it propagates — the consumer
  # stores it, signs it, or submits it, and the failure surfaces somewhere with
  # no connection to this call.
  #
  # REJECT rather than repair, deliberately. The gaps in hdf-cli's output are
  # OSCAL-REQUIRED content — `reviewed-controls` (what the assessment actually
  # covered), `finding/description`, `characterization/origin`. Synthesising
  # them here would produce a document that passes the schema and misstates the
  # assessment, which is the same mistake as an exporter inventing required
  # content (#816) or hdf-cli 3.3.2 inventing a POA&M deadline (#764).
  # Determining what a scan reviewed is the converter's job, and it is tracked
  # upstream at mitre/hdf-libs#184.
  #
  # The error names every schema violation, so the caller can see it is an
  # upstream converter limitation rather than something wrong with their input.
  def validate_oscal!(model_type, oscal)
    OscalSchemaValidationService.validate!(model_type, oscal)
    oscal
  end

  # When a tenant hosts evidence in SPARC for the given AuthorizationBoundary,
  # merge those records as OSCAL back-matter `resource` entries. Pass-through
  # when boundary is nil — tenants who don't use SPARC for evidence pay no
  # cost.
  def enrich_back_matter(oscal, boundary)
    return oscal if boundary.nil?

    root_key = oscal.keys.first
    return oscal if root_key.nil?

    oscal[root_key] ||= {}
    oscal[root_key][BACK_MATTER] ||= {}
    oscal[root_key][BACK_MATTER]["resources"] ||= []

    boundary.evidences.includes(:attestations, :evidence_control_links).find_each do |evidence|
      oscal[root_key][BACK_MATTER]["resources"] << build_resource(evidence)
    end

    oscal
  end

  def build_resource(evidence)
    # Version-aware identity (#680): the resource uuid is the CURRENT content
    # version, while the resolver href (location) stays stable — a stable link
    # with a changing uuid gives drift detection.
    version = evidence.current_artifact_version
    resource = { "uuid" => (version&.uuid || evidence.uuid), "title" => evidence.title }
    resource["description"] = evidence.description if evidence.description.present?

    props = []
    props << { "name" => "logical-id",    "value" => evidence.uuid }
    props << { "name" => "reviewed-date", "value" => version.reviewed_at.utc.iso8601 } if version&.reviewed_at
    props << { "name" => "source",        "value" => evidence.source }                 if evidence.source.present?
    props << { "name" => "evidence-type", "value" => evidence.evidence_type }          if evidence.evidence_type.present?
    props << { "name" => "status",        "value" => evidence.status }                 if evidence.status.present?
    # Ordered for the same reason the CMS export is (#1177): this is a
    # DELIVERED OSCAL artefact, and the links carry no order of their own, so
    # unordered iteration made the prop sequence vary between runs and the
    # output non-reproducible. `ControlId.padded` is the codebase's sort form
    # and orders naturally, so `ac-10` follows `ac-2` rather than preceding it.
    evidence.evidence_control_links
            .sort_by { |link| [ ControlId.padded(link.control_id), link.id.to_i ] }
            .each do |link|
      props << { "name" => "control-id", "value" => link.control_id }
    end
    evidence.attestations.each do |a|
      props << {
        "name" => "attestation",
        "value" => "#{a.attester_name} (#{a.role_label}) attested #{a.attested_at.utc.iso8601} — status #{a.status}"
      }
    end
    resource["props"] = props if props.any?

    if evidence.original_filename.present?
      # Durable, immutable resolver href (#680) — survives rename/re-upload/
      # signed-URL rotation, and is absolute so external OSCAL consumers resolve.
      rlink = { "href" => evidence.oscal_resolver_url }
      rlink["media-type"] = evidence.file_content_type if evidence.file_content_type.present?
      resource["rlinks"] = [ rlink ]
    end

    resource
  end
end
