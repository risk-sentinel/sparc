# frozen_string_literal: true

# API equivalent of the durable artifact resolver (#680, Phase 1). Resolves an
# immutable artifact UUID to a freshly-signed download URL for programmatic
# consumers (the UI / external OSCAL tooling). Token-authenticated via
# Api::V1::BaseController.
#
# NIST 800-53: AU-10 (non-repudiation), SI-12 (information handling/retention),
# CM-8 (artifact inventory).
class Api::V1::ArtifactsController < Api::V1::BaseController
  include ArtifactResolvable

  # GET /api/v1/artifacts/:uuid
  def show
    evidence = find_artifact!(params[:uuid])
    render json: {
      data: {
        uuid:       evidence.uuid,
        title:      evidence.title,
        # Prefer the denormalized columns, fall back to the attached blob so the
        # resolver reports correct metadata even if compute_file_hash! never ran.
        filename:   evidence.original_filename.presence || evidence.file.filename.to_s,
        media_type: evidence.file_content_type.presence || evidence.file.content_type,
        url:        signed_artifact_url(evidence)
      }
    }
  end
end
