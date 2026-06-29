# frozen_string_literal: true

# Shared lookup + signing logic for the durable artifact resolver (#680),
# used by both the web (ArtifactsController) and API
# (Api::V1::ArtifactsController) resolvers.
#
# The resolver separates a STABLE identity (the artifact's immutable UUID,
# surfaced as /artifacts/:uuid in exported OSCAL back-matter) from the MUTABLE
# location (a short-lived signed blob URL). Because a freshly-signed URL is
# generated on every request, the durable /artifacts/:uuid reference never
# expires and survives evidence rename, file re-upload, and signed-URL rotation.
#
# NIST 800-53: AU-10 (non-repudiation via stable artifact identity),
# SI-12 (information handling & retention), CM-8 (artifact inventory).
module ArtifactResolvable
  extend ActiveSupport::Concern

  private

  # Resolve an artifact (Evidence) by its immutable UUID. Raises
  # ActiveRecord::RecordNotFound when the UUID is unknown or the record has no
  # file attached (nothing to resolve) — both controllers translate that to 404.
  def find_artifact!(uuid)
    evidence = Evidence.find_by!(uuid: uuid)
    raise ActiveRecord::RecordNotFound, "artifact #{uuid} has no attached file" unless evidence.file.attached?

    evidence
  end

  # Freshly-signed, time-limited download URL for the artifact's blob,
  # regenerated on every call. Served from the cookieless userdata host (#515)
  # when configured, otherwise the current request host.
  def signed_artifact_url(evidence, disposition: "attachment")
    opts = { disposition: disposition }
    if (host = SparcConfig.userdata_host).present?
      opts[:host]     = host
      opts[:protocol] = SparcConfig.userdata_protocol
    end
    rails_blob_url(evidence.file, **opts)
  end
end
