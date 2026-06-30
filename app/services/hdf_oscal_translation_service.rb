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
    enrich_back_matter(oscal, boundary)
  end

  # HDF results → OSCAL Plan of Action and Milestones
  # @param hdf_input [String, IO]
  # @param boundary [AuthorizationBoundary, nil] optional back-matter enrichment
  # @return [Hash] OSCAL POAM document
  def hdf_to_oscal_poam(hdf_input, boundary: nil)
    oscal = @runner.convert(hdf_input, from: "hdf", to: OSCAL_POAM)
    enrich_back_matter(oscal, boundary)
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
    enrich_back_matter(oscal, boundary)
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

  # When a tenant hosts evidence in SPARC for the given AuthorizationBoundary,
  # merge those records as OSCAL back-matter `resource` entries. Pass-through
  # when boundary is nil — tenants who don't use SPARC for evidence pay no
  # cost.
  def enrich_back_matter(oscal, boundary)
    return oscal if boundary.nil?

    root_key = oscal.keys.first
    return oscal if root_key.nil?

    oscal[root_key] ||= {}
    oscal[root_key]["back-matter"] ||= {}
    oscal[root_key]["back-matter"]["resources"] ||= []

    boundary.evidences.includes(:attestations, :evidence_control_links).find_each do |evidence|
      oscal[root_key]["back-matter"]["resources"] << build_resource(evidence)
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
