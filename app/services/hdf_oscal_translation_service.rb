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

  # OSCAL POAM → HDF Amendments
  # @param oscal_input [String, IO] file path or IO of an OSCAL POAM JSON/XML
  # @return [Hash] HDF Amendments document
  def oscal_poam_to_hdf_amendments(oscal_input)
    amendments = @runner.convert(oscal_input, from: OSCAL_POAM)
    # Defense-in-depth: round-trip the result through `hdf amend verify`
    # so we don't serve a payload that won't `hdf amend apply` cleanly.
    Tempfile.create([ "hdf-amendments-", ".json" ]) do |f|
      f.write(JSON.generate(amendments))
      f.flush
      @runner.amend_verify(f.path)
    end
    amendments
  end

  private

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
    evidence.evidence_control_links.each do |link|
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
