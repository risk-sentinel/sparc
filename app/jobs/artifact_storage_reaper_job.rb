# frozen_string_literal: true

# #690 (Phase 3 of #680) — keeps artifact storage and OSCAL references healthy
# now that purge is off by default and every version's content is retained.
#
# Two sweeps, both REPORT-ONLY by default:
#
#   1. Orphan-blob reaper — Active Storage blobs no longer referenced by any
#      attachment (Evidence#file / ArtifactVersion#content), e.g. left behind by
#      a hard-deleted evidence. Retained versions are still *attached*, so they
#      are never candidates. Destructive purge is gated on
#      SPARC_ARTIFACT_REAPER_PURGE (coordinate with the S3 lifecycle policy,
#      sparc-iac#476). A grace window (min-age) protects in-flight uploads.
#
#   2. Dangling back-matter href scan — BackMatterResource rows whose href points
#      at an /artifacts/:uuid (or /artifacts/versions/:uuid) that no longer
#      resolves to an Evidence / ArtifactVersion. Reported only (never deleted —
#      that is document drift for a human to reconcile, not storage garbage).
#
# Scheduled in config/recurring.yml on a multi-day interval.
#
# NIST 800-53: SI-12 (information handling / retention), CM-8 (inventory hygiene),
# AU-6 (surfacing drift for review).
class ArtifactStorageReaperJob < ApplicationJob
  queue_as :default

  # /artifacts/<uuid> and /artifacts/versions/<uuid>.
  ARTIFACT_UUID_RE = %r{/artifacts/(?:versions/)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})}i

  def perform
    report = {
      orphan_blobs:   sweep_orphan_blobs,
      dangling_hrefs: scan_dangling_hrefs
    }
    log_report(report)
    report
  end

  private

  def sweep_orphan_blobs
    cutoff = SparcConfig.artifact_reaper_min_age_hours.hours.ago
    scope  = ActiveStorage::Blob.unattached
                                .where(ActiveStorage::Blob.arel_table[:created_at].lt(cutoff))

    unreferenced = scope.count
    byte_size    = scope.sum(:byte_size)
    purge        = SparcConfig.artifact_reaper_purge?
    purged       = 0

    if purge
      scope.find_each do |blob|
        blob.purge_later
        purged += 1
      end
    end

    { unreferenced: unreferenced, byte_size: byte_size, cleaning_enabled: purge, purged: purged }
  end

  def scan_dangling_hrefs
    dangling = []
    BackMatterResource.where.not(href: [ nil, "" ]).find_each do |bmr|
      uuid = bmr.href.to_s[ARTIFACT_UUID_RE, 1]
      next if uuid.blank?
      next if Evidence.exists?(uuid: uuid) || ArtifactVersion.exists?(uuid: uuid)

      dangling << { back_matter_resource_id: bmr.id, href: bmr.href, uuid: uuid }
    end
    dangling
  end

  def log_report(report)
    ob = report[:orphan_blobs]
    Rails.logger.info(
      "[ArtifactStorageReaper] orphan_blobs=#{ob[:unreferenced]} bytes=#{ob[:byte_size]} " \
      "cleaning=#{ob[:cleaning_enabled]} purged=#{ob[:purged]} " \
      "dangling_hrefs=#{report[:dangling_hrefs].size}"
    )
    report[:dangling_hrefs].each do |d|
      Rails.logger.warn(
        "[ArtifactStorageReaper] dangling_href back_matter_resource_id=#{d[:back_matter_resource_id]} " \
        "uuid=#{d[:uuid]} href=#{d[:href]}"
      )
    end
  end
end
