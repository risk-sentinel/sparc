# frozen_string_literal: true

# #785 Pass 2.1 — report the object-storage backend at boot, and refuse to run
# on ephemeral local disk in production.
#
# The single most damaging storage mistake is deploying to ECS/EKS on local
# disk: uploads work, then a redeploy silently eats them (the container
# filesystem is ephemeral). The config lives in storage.yml + SPARC_STORAGE_URL,
# which operators don't watch, so this makes the footgun impossible to reach by
# accident — the same principle as the DB-TLS posture check
# (zz_database_tls_posture.rb), but a HARD FAIL rather than a warning, because
# silent data loss is worse than an unauthenticated-but-encrypted DB connection.
#
# Escape hatch: SPARC_ALLOW_LOCAL_STORAGE=true for legitimate single-node or
# mounted-volume deployments that really do want local disk.
#
# NIST 800-53: CP-9 (system backup / data durability), SI-12 (information
# handling and retention).

Rails.application.config.after_initialize do
  next unless Rails.env.production?

  local   = StorageUrl.local?
  allowed = ENV.fetch("SPARC_ALLOW_LOCAL_STORAGE", "false") == "true"

  if local && !allowed
    raise <<~MSG
      [SPARC] Object storage resolves to LOCAL DISK in production.
      On ECS/EKS the container filesystem is ephemeral — every uploaded document,
      evidence file, and artifact would be lost on the next redeploy.

      Set object storage explicitly, e.g.:
        SPARC_STORAGE_URL=s3://your-bucket           (region from AWS_REGION)
        SPARC_STORAGE_URL=s3://your-bucket?region=us-east-1

      If this deployment genuinely uses durable local storage (single node or a
      mounted volume), set SPARC_ALLOW_LOCAL_STORAGE=true to acknowledge it.
      See docs/OBJECT_STORAGE.md.
    MSG
  elsif local
    Rails.logger.warn(
      "[SPARC] Object storage: LOCAL DISK in production (SPARC_ALLOW_LOCAL_STORAGE=true). " \
      "Durable only if backed by a persistent volume — uploads are lost on redeploy otherwise."
    )
  else
    detail = StorageUrl.service == :amazon ? " bucket=#{StorageUrl.bucket} region=#{StorageUrl.region}" : ""
    Rails.logger.info("[SPARC] Object storage: #{StorageUrl.service}#{detail}.")
  end
end
