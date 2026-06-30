# frozen_string_literal: true

# Gives Evidence a version history (#680). A new ArtifactVersion is minted
# whenever the artifact's *material* state changes — the file (file_hash), any
# attestation's attester/role/reviewed-date/status, or the evidence status —
# while the title + control linkage (the logical "name and location") stay
# stable. The current version's UUID is what the OSCAL back-matter
# `resource.uuid` carries, so a stable link + a changing UUID = drift detection.
#
# Versioning is driven at the MODEL layer (callbacks), so it fires regardless of
# entry point (web, API, console, bulk).
module ArtifactVersionable
  extend ActiveSupport::Concern

  included do
    has_many :artifact_versions, dependent: :destroy
    after_commit :version_on_material_change, on: [ :create, :update ]
  end

  # Current (latest, non-superseded) version. Lazily minted so evidence created
  # before the backfill — or accessed outside a save — always has one, and OSCAL
  # emission never sees a nil version.
  def current_artifact_version
    return nil unless versionable_artifact?

    artifact_versions.live.chronological.last || mint_artifact_version!(reason: "initial")
  end

  # A version is only meaningful once the content hash is computed — guards
  # against the transient `file.attach`→`after_commit` that fires before
  # compute_file_hash! has populated file_hash.
  def versionable_artifact?
    file.attached? && file_hash.present?
  end

  # SHA-256 over the material content: file hash + each attestation's
  # attester/role/reviewed-date/status (sorted) + evidence status. Title and
  # other non-material fields are intentionally excluded.
  def artifact_fingerprint
    atts = material_attestations.map do |a|
      [ a.attester_name, a.role, a.attested_at&.utc&.iso8601, a.status ].join("|")
    end.sort
    Digest::SHA256.hexdigest([ file_hash, status, *atts ].join("\n"))
  end

  # Mint a new version only when the material fingerprint differs from the
  # current one (idempotent — safe to call from multiple callbacks).
  def record_artifact_version_if_changed(reason: "update")
    return unless versionable_artifact?

    fingerprint = artifact_fingerprint
    current = artifact_versions.live.chronological.last
    return current if current && current.fingerprint == fingerprint

    mint_artifact_version!(reason: reason, fingerprint: fingerprint, supersede: current)
  end

  def mint_artifact_version!(reason:, fingerprint: nil, supersede: nil)
    fingerprint ||= artifact_fingerprint
    version = nil
    transaction do
      supersede&.update!(superseded_at: Time.current)
      version = artifact_versions.create!(
        uuid:              SecureRandom.uuid,
        fingerprint:       fingerprint,
        file_hash:         file_hash,
        attester_snapshot: attestation_snapshot,
        evidence_status:   status,
        reviewed_at:       material_attestations.maximum(:attested_at) || updated_at,
        change_reason:     reason
      )
      # Retain this version's content by reference (no copy — #686 tracks the
      # copy-per-version alternative). Metadata-only versions share the current
      # blob; a file change introduces a new blob the next version references.
      version.content.attach(file.blob) if file.attached?
    end
    version
  end

  private

  # Read attestations fresh from the DB so the fingerprint is correct even when
  # called across the attestation→evidence callback boundary (stale caches).
  def material_attestations
    Attestation.where(evidence_id: id).order(:id)
  end

  def attestation_snapshot
    material_attestations.map do |a|
      {
        "attester_name" => a.attester_name,
        "role"          => a.role,
        "attested_at"   => a.attested_at&.utc&.iso8601,
        "status"        => a.status
      }
    end
  end

  def version_on_material_change
    record_artifact_version_if_changed
  end
end
