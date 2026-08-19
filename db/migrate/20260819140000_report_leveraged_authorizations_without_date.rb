# #988 — report the leveraged authorizations that name no authorization date,
# so an operator upgrading across this release is told what exists rather than
# discovering it when an SSP export refuses to validate.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row
# is recorded at db:migrate time and the body runs post-boot, so an instance
# with a large corpus still comes up immediately.
#
# ── It deliberately writes NOTHING ─────────────────────────────────────────
#
# `date_authorized` is now required, so it is tempting to fill the blanks in.
# There is no value that would be TRUE. The date is when the OTHER system
# received its authorization — a fact about someone else's ATO that SPARC does
# not hold and cannot derive. Defaulting it to the row's `created_at`, or to
# today, would fabricate the authorization evidence the field exists to record,
# and a leveraged authorization dated wrongly is worse than one visibly
# undated. So this reports, and a human supplies each date knowingly.
#
# ── Why an undated row is not merely incomplete ────────────────────────────
#
# Leveraging means relying on another system's authorization. A row with no
# date claims to inherit an authorization that, as far as the record goes, does
# not exist. OSCAL agrees: `date-authorized` is mandatory on every
# `leveraged-authorization`, so ONE undated row makes every SSP on the
# leveraging boundary fail export validation in all three formats — and both
# export builders omitted the property instead of refusing to build the entry,
# so the failure surfaced at schema validation with nothing pointing at the row
# responsible.
#
# ── Idempotency ────────────────────────────────────────────────────────────
#
# It only reads. Re-running re-reports whatever is still undated, which is the
# desired behaviour: the count falls as an operator works through them, and
# reaching zero is the signal that the work is done.
class ReportLeveragedAuthorizationsWithoutDate < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      report_undated_leveraged_authorizations
    end
  end

  def down
    # Nothing was written.
  end

  private

  def report_undated_leveraged_authorizations
    undated = LeveragedAuthorization.where(date_authorized: nil)
    count   = undated.count

    if count.zero?
      Rails.logger.info(
        { leveraged_authorizations_without_date: { count: 0, note: "none found" } }.to_json
      )
      return
    end

    Rails.logger.warn(
      {
        leveraged_authorizations_without_date: {
          count: count,
          # Bounded: an operator needs to recognise them, not receive the whole
          # table in a log line. The leveraging boundary is what they will go
          # looking for, so it is named rather than left as an id.
          sample: undated.limit(20).includes(:leveraging_boundary).map { |la|
            { id: la.id,
              name: la.name,
              leveraging_boundary: la.leveraging_boundary&.name }
          },
          note: "no date_authorized. Every SSP on the leveraging boundary will " \
                "fail OSCAL export validation until each is dated. Set the date " \
                "on the boundary's leveraged-authorization record; it cannot be " \
                "derived, because it belongs to the leveraged system's ATO."
        }
      }.to_json
    )

    AuditEvent.log(
      action: "leveraged_authorizations_without_date_reported",
      metadata: { total: count }
    )
  end
end
