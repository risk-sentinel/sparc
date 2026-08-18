# #959 — report the authoritative back-matter resources that used to be embedded
# in every export and, from this release, are carried only by documents that
# actually reference them.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row is
# recorded at db:migrate time and the body runs post-boot.
#
# ── It changes nothing, deliberately ──────────────────────────────────────
#
# The owner's disposition, matching the #952 precedent: report, assign nothing.
# Every alternative involves inventing a fact. Scoping these rows to an
# organization would need lineage many of them do not have; clearing
# `globally_available` would silently remove resources some deployments rely on;
# linking them to documents would assert a relationship nobody made. The rows
# are unchanged and still reachable — what changed is that a document carries
# one only when it points at it.
#
# The behaviour change this reports is worth an operator's attention because it
# is visible in output they may diff: an export that previously listed every
# authoritative resource in the instance now lists the ones the document uses.
# On the estate where #959 was measured that was 12 resources per document, all
# of them UI-smoke residue, in all 12 reference artifacts.
#
# ── Idempotency ────────────────────────────────────────────────────────────
#
# It only reads. Re-running re-reports current state, which is the desired
# behaviour: the count falls as an operator links or archives resources, and
# reaching zero means nothing is left unreferenced.
class ReportUnscopedAuthoritativeBackMatter < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      report_unreferenced_authoritative
    end
  end

  def down
    # Nothing was written.
  end

  private

  def report_unreferenced_authoritative
    authoritative = BackMatterResource.active.where(source: "authoritative")
    total = authoritative.count

    if total.zero?
      Rails.logger.info({ unscoped_authoritative_back_matter: { count: 0, note: "none found" } }.to_json)
      return
    end

    # Referenced anywhere = attached to a document, or linked to any control.
    # A resource matching neither was previously carried by every export and is
    # now carried by none, which is the case an operator most needs to see.
    attached_uuids = BackMatterResource.active
                                       .where(source: "authoritative")
                                       .where.not(resourceable_id: nil)
                                       .pluck(:uuid)
    linked_uuids = BackMatterResource.active
                                     .where(source: "authoritative")
                                     .where(id: ControlBackMatterLink.select(:back_matter_resource_id))
                                     .pluck(:uuid)
    referenced = (attached_uuids + linked_uuids).uniq

    unreferenced = authoritative.where.not(uuid: referenced)
    count = unreferenced.count

    Rails.logger.warn(
      {
        unscoped_authoritative_back_matter: {
          authoritative_total: total,
          no_longer_embedded_anywhere: count,
          sample: unreferenced.limit(20).pluck(:id, :title).map { |id, title| { id: id, title: title } },
          note: "#959 — an export now carries an authoritative resource only when the document " \
                "references it. These are referenced by no document and no control, so they " \
                "appear in no export. Nothing was changed: link, archive or leave them."
        }
      }.to_json
    )

    AuditEvent.log(
      action: "unscoped_authoritative_back_matter_reported",
      metadata: { authoritative_total: total, no_longer_embedded_anywhere: count }
    )
  end
end
