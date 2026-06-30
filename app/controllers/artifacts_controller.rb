# frozen_string_literal: true

# Durable artifact resolver (#680, Phase 1). Resolves an immutable artifact
# UUID emitted in OSCAL back-matter (/artifacts/:uuid) to a freshly-signed,
# time-limited download URL — so exported back-matter hrefs stay valid across
# evidence rename, file re-upload, and signed-URL expiry.
#
# Requires an authenticated session (inherited from ApplicationController via
# `require_authentication`), matching the access model of the evidence pages
# the resolver points at. The Api::V1 equivalent (token-authenticated) lives in
# Api::V1::ArtifactsController.
#
# NIST 800-53: AU-10 (non-repudiation), SI-12 (information handling/retention),
# CM-8 (artifact inventory).
class ArtifactsController < ApplicationController
  include ArtifactResolvable

  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end

  # GET /artifacts/:uuid
  def show
    evidence = find_artifact!(params[:uuid])
    redirect_to signed_artifact_url(evidence), allow_other_host: true
  end

  # GET /artifacts/versions/:uuid — resolve a specific retained content version.
  def version
    artifact_version = find_artifact_version!(params[:uuid])
    redirect_to signed_version_url(artifact_version), allow_other_host: true
  end
end
