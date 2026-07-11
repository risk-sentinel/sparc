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

  # GET /api/v1/artifacts/:uuid — resolves the stable logical identity to the
  # CURRENT content (the link/location is stable; #680).
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
        current_version_uuid: evidence.current_artifact_version&.uuid,
        url:        signed_artifact_url(evidence)
      }
    }
  end

  # GET /api/v1/artifacts/versions/:uuid — resolve a specific content version
  # (#680): its retained content + drift metadata (as-of, superseded, current).
  def version
    artifact_version = find_artifact_version!(params[:uuid])
    evidence = artifact_version.evidence
    render json: {
      data: {
        version_uuid:         artifact_version.uuid,
        logical_id:           evidence.uuid,
        reviewed_at:          artifact_version.reviewed_at,
        superseded_at:        artifact_version.superseded_at,
        current:              artifact_version.current?,
        current_version_uuid: evidence.current_artifact_version&.uuid,
        media_type:           artifact_version.content.content_type,
        url:                  signed_version_url(artifact_version)
      }
    }
  end

  # GET /api/v1/artifacts/:uuid/versions — the artifact's content-version
  # timeline with the review delta between consecutive versions (#685).
  # Enablement: SPARC exposes the cadence data; the consuming system makes the
  # compliance judgment.
  def versions
    evidence = find_artifact!(params[:uuid])
    prev_reviewed = nil
    serialized = evidence.artifact_versions.chronological.map do |v|
      delta = (((v.reviewed_at - prev_reviewed) / 1.day).round if v.reviewed_at && prev_reviewed)
      prev_reviewed = v.reviewed_at if v.reviewed_at
      {
        version_uuid:      v.uuid,
        fingerprint:       v.fingerprint,
        reviewed_at:       v.reviewed_at,
        superseded_at:     v.superseded_at,
        current:           v.current?,
        evidence_status:   v.evidence_status,
        change_reason:     v.change_reason,
        review_delta_days: delta
      }
    end
    render json: {
      data: {
        uuid:                 evidence.uuid,
        title:                evidence.title,
        current_version_uuid: evidence.current_artifact_version&.uuid,
        linked_control_ids:   evidence.linked_control_ids,
        versions:             serialized
      },
      meta: { count: serialized.size }
    }
  end

  # GET /api/v1/artifacts/:uuid/freshness — review-cadence freshness as DATA
  # (#685, NIST CA-7): last reviewed, the attestation-declared cadence, next
  # due, overdue. SPARC surfaces this; the consuming GRC system asserts
  # compliance ("are teams refreshing within the ODP frequency").
  def freshness
    evidence = find_artifact!(params[:uuid])
    last_reviewed = evidence.artifact_versions.maximum(:reviewed_at)
    # Binding cadence = the shortest declared interval across the attestations.
    frequency = evidence.attestations
                        .where.not(frequency: [ nil, "ad_hoc" ])
                        .map(&:frequency)
                        .min_by { |f| Attestation.interval_for(f) || Float::INFINITY }
    interval = Attestation.interval_for(frequency)
    next_due = (last_reviewed + interval if last_reviewed && interval)
    overdue  = next_due ? next_due < Time.current : false
    render json: {
      data: {
        uuid:                   evidence.uuid,
        title:                  evidence.title,
        linked_control_ids:     evidence.linked_control_ids,
        last_reviewed_at:       last_reviewed,
        review_frequency:       frequency,
        review_frequency_label: (Attestation::FREQUENCY_LABELS[frequency] if frequency),
        next_review_due:        next_due,
        overdue:                overdue,
        days_overdue:           (overdue ? ((Time.current - next_due) / 1.day).ceil : 0),
        note: "Enablement only: SPARC exposes artifact freshness as data; the " \
              "compliance assertion is made by the consuming system."
      }
    }
  end
end
