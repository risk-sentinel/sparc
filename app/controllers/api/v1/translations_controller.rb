# Stateless translation endpoints between HDF and OSCAL artefacts (#449).
#
# These endpoints do not persist anything to SPARC's database — tenant
# compliance state remains in the tenant's own systems. SPARC's value
# here is centralizing the MITRE hdf-libs CLI install, pinning the
# version, and exposing the translation as authenticated REST.
#
# Endpoints:
#   POST /api/v1/oscal/sar_from_hdf              — HDF results → OSCAL SAR
#   POST /api/v1/oscal/poam_from_hdf             — HDF results → OSCAL POAM
#   POST /api/v1/oscal/poam_from_amendments      — HDF Amendments → OSCAL POAM
#   POST /api/v1/hdf/amendments_from_oscal_poam  — OSCAL POAM → HDF Amendments
#
# Payload may arrive as either:
#   - multipart/form-data with a `:file` field, OR
#   - raw JSON request body (Content-Type: application/json)
#
# NIST 800-53 controls covered:
#   IA-2  Identification and Authentication (Bearer token required)
#   AC-3  Access Enforcement (any authenticated user; no extra permission required)
#   AU-12 Audit Record Generation (each translation logged)
#   CA-7  Continuous Monitoring (translation surface for tenant CI pipelines)
#   SI-2  Flaw Remediation (amendments output gates tenant pipelines)
#
class Api::V1::TranslationsController < Api::V1::BaseController
  rescue_from HdfRunner::Error do |e|
    # A "no converter found" failure means the bundled hdf-cli doesn't support
    # this translation path — currently raw hdf→oscal-poam, which 3.2.0 removed
    # and which upstream has confirmed is permanent by design rather than an
    # oversight ("a POA&M is not so much a 'result set' as it is a 'document
    # enhancing a result set'" — mitre/hdf-libs#104). POA&M is produced from an
    # HDF *amendments* doc (hdf-amendments → oscal-poam), not from raw scanner
    # HDF. Re-verified against the 3.4.1 convert catalog (#764).
    #
    # Match only the stable literal. The follow-on line hdf-cli emits ("The
    # 'hdf' format can convert to: …") is map-iteration ordered and therefore
    # non-deterministic — never match on it.
    #
    # Surface a clear 501 rather than a generic 422 so callers can distinguish
    # "unsupported path" from "bad input".
    if e.message.include?("no converter found")
      render json: {
        error: "Translation path not available in the bundled hdf-cli",
        details: e.message,
        note: "The direct hdf→oscal-poam converter was removed in hdf-cli 3.2.0 and is permanent by design; OSCAL POA&M is sourced from hdf-amendments. See https://github.com/mitre/hdf-libs/issues/104"
      }, status: :not_implemented

    # 3.4.1 (#764) stopped fabricating expiry dates for POA&M items lacking a
    # deadline and now fails loud instead. That is a correction — 3.3.2 exited 0
    # by inventing conversion-time + 1 year — but it is a NEW exit-1 path, and
    # the fix is entirely in the caller's input. Surface it distinctly so the
    # response says what to add rather than burying it in a generic 422.
    elsif e.message.include?("no related risk carries a usable deadline")
      render json: {
        error: "POA&M is missing a remediation deadline",
        details: e.message,
        note: "Every poam-item needs a related risk carrying a deadline. Populate risks[].deadline in the source OSCAL POA&M. Prior to hdf-cli 3.4.1 this succeeded with a fabricated date."
      }, status: :unprocessable_entity
    else
      render json: {
        error: "hdf-libs translation failed",
        details: e.message,
        stderr: e.stderr.to_s.lines.first(20).join.strip
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/oscal/sar_from_hdf
  def sar_from_hdf
    with_uploaded_payload do |path|
      with_optional_boundary do |boundary|
        result = translation_service.hdf_to_oscal_sar(path, boundary: boundary)
        audit_log("translation_hdf_to_oscal_sar",
                  metadata: { authorization_boundary_id: boundary&.id })
        render json: result
      end
    end
  end

  # POST /api/v1/oscal/poam_from_hdf
  def poam_from_hdf
    with_uploaded_payload do |path|
      with_optional_boundary do |boundary|
        result = translation_service.hdf_to_oscal_poam(path, boundary: boundary)
        audit_log("translation_hdf_to_oscal_poam",
                  metadata: { authorization_boundary_id: boundary&.id })
        render json: result
      end
    end
  end

  # POST /api/v1/oscal/poam_from_amendments
  #
  # hdf-cli 3.2.0 removed the direct hdf→oscal-poam converter; an OSCAL POA&M is
  # now produced from an HDF *amendments* document via
  # `hdf convert --from hdf-amendments --to oscal-poam` (verified against the
  # 3.2.0 convert catalog). This is the supported replacement for the removed
  # raw-HDF→POA&M path that `poam_from_hdf` now 501s. See #663, mitre/hdf-libs#104.
  def poam_from_amendments
    with_uploaded_payload do |path|
      with_optional_boundary do |boundary|
        result = translation_service.oscal_poam_from_hdf_amendments(path, boundary: boundary)
        audit_log("translation_hdf_amendments_to_oscal_poam",
                  metadata: { authorization_boundary_id: boundary&.id })
        render json: result
      end
    end
  end

  # POST /api/v1/hdf/amendments_from_oscal_poam
  def amendments_from_oscal_poam
    with_uploaded_payload do |path|
      result = translation_service.oscal_poam_to_hdf_amendments(path)
      audit_log("translation_oscal_poam_to_hdf_amendments")
      render json: result
    end
  end

  private

  def translation_service
    @translation_service ||= HdfOscalTranslationService.new
  end

  # Yield a file path the runner can read from. Accepts multipart upload
  # via :file or a raw request body.
  def with_uploaded_payload
    if params[:file].respond_to?(:tempfile)
      yield params[:file].tempfile.path
    elsif request.raw_post.present?
      Tempfile.create([ "translation-input-", ".json" ]) do |f|
        f.binmode
        f.write(request.raw_post)
        f.flush
        yield f.path
      end
    else
      render json: {
        error: "No payload supplied",
        details: "Provide a multipart :file upload or a raw JSON request body"
      }, status: :bad_request
    end
  end

  # Optional back-matter enrichment. When `:authorization_boundary_id` is
  # supplied, the caller must have evidence.read for that boundary; SPARC
  # then merges the boundary's Evidence records into the OSCAL output's
  # back-matter as `resource` entries with attestation provenance props.
  def with_optional_boundary
    boundary_param = params[:authorization_boundary_id]
    return yield(nil) if boundary_param.blank?

    boundary = AuthorizationBoundary.find(boundary_param)

    unless current_user.admin? || current_user.has_permission?("evidence.read")
      raise NotAuthorizedError, "Not authorized to read evidence for this boundary"
    end

    yield boundary
  end
end
