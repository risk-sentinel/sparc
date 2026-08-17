# #952 — report the SSP/SAP/SAR/POA&M rows that belong to no authorization
# boundary, so an operator upgrading across this release is told what exists
# rather than discovering it from a filter.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row
# is recorded at db:migrate time and the body runs post-boot, so an instance
# with a large corpus still comes up immediately.
#
# ── It deliberately assigns NOTHING ────────────────────────────────────────
#
# A boundary is now mandatory for these four types, so it is tempting to attach
# the strays to something. There is nothing to attach them to that would be
# TRUE. A system security plan names one system; picking a boundary for it —
# "the only one", "the first one", "the one the seed made" — invents an
# authorization relationship nobody asserted, and an SSP filed under the wrong
# ATO is worse than one visibly filed under none. So this reports, and #929's
# attach flow is how a human resolves each case knowingly.
#
# Until they are resolved these rows are no longer visible to every signed-in
# user: `boundary_scoped SspDocument, …, global_fallback: false` drops the
# nil-boundary fallback for the per-system types, leaving them to
# Instance-Admins. That is the security half of #952 and it needs no data
# change, which is why this migration can afford to be purely advisory.
#
# ── Idempotency ────────────────────────────────────────────────────────────
#
# It only reads. Re-running re-reports whatever is still unattached, which is
# exactly the desired behaviour: the count falls as an operator works through
# them and reaching zero is the signal that the work is done.
class ReportBoundaryLessDocuments < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  REPORTED_TYPES = %w[SspDocument SapDocument SarDocument PoamDocument].freeze

  def up
    defer_data_migration do
      report_boundary_less_documents
    end
  end

  def down
    # Nothing was written.
  end

  private

  def report_boundary_less_documents
    total = 0

    REPORTED_TYPES.each do |type_name|
      klass = type_name.safe_constantize
      next if klass.nil?
      next unless klass.column_names.include?("authorization_boundary_id")

      # `unscoped` so soft-deleted rows are not counted: they are not visible
      # anywhere and attaching them would be busywork (#967).
      orphans = klass.where(authorization_boundary_id: nil)
      count   = orphans.count
      total  += count
      next if count.zero?

      Rails.logger.warn(
        {
          boundary_less_documents: {
            document_type: type_name,
            count: count,
            # Bounded: an operator needs to recognise them, not receive the
            # whole table in a log line.
            sample: orphans.limit(20).pluck(:id, :name).map { |id, name| { id: id, name: name } },
            note: "no authorization boundary; visible to Instance-Admins only. " \
                  "Attach each from the boundary's Artifact Summary (#929)."
          }
        }.to_json
      )
    end

    if total.zero?
      Rails.logger.info({ boundary_less_documents: { count: 0, note: "none found" } }.to_json)
      return
    end

    AuditEvent.log(
      action: "boundary_less_documents_reported",
      metadata: { total: total, types: REPORTED_TYPES }
    )
  end
end
