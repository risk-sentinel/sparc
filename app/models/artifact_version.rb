# frozen_string_literal: true

# A single content-version of an evidence artifact (#680). Minted whenever the
# artifact's *material* state changes (file, attestations, or status). Its
# `uuid` is the version-aware identity emitted in OSCAL back-matter
# `resource.uuid`. By default `content` retains that version's blob by reference
# (no duplication); with SPARC_ARTIFACT_COPY_PER_VERSION=true each version owns an
# independent physical copy for per-version WORM/immutability (#686).
#
# The logical identity (title + control linkage) lives on the Evidence and is
# stable; this record is the *version*. Same name+location across documents
# with a different ArtifactVersion uuid ⇒ drift; the `reviewed_at` dates give
# the delta for ODP cadence checks (#685).
#
# NIST 800-53: AU-10 (non-repudiation via stable, version-aware identity),
# SI-12 (information handling/retention), CA-7 (continuous-monitoring enabler).
class ArtifactVersion < ApplicationRecord
  belongs_to :evidence
  has_one_attached :content

  scope :live, -> { where(superseded_at: nil) }
  scope :chronological, -> { order(:created_at) }

  def current?
    superseded_at.nil?
  end

  def superseded?
    superseded_at.present?
  end
end
