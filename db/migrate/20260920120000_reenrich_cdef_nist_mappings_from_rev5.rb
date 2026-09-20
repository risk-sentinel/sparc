# frozen_string_literal: true

# #1103 — existing deployments are carrying rev4 NIST ids in a rev5 mapping, and
# are missing the coverage the re-vendor adds. Neither fixes itself on deploy.
#
# ── Why the seed does not cover this ───────────────────────────────────────
#
# db/seeds/converters.rb loads entries only `if converter.converter_entries.none?`.
# That guard is right — it stops a re-seed trampling operator edits — but it also
# means an instance seeded before this release keeps its 106-rule, rev4 AWS
# Config converter forever, no matter how many times the vendored file is
# updated in the image. The data has to be pushed.
#
# ── What was wrong ─────────────────────────────────────────────────────────
#
# The second hop of the AWS Security Hub -> NIST chain plucks the AWS Config
# converter's `target_id` verbatim; it does no revision translation. The
# converter it feeds is declared `target_rev: "5"`, but the vendored MITRE data
# was rev4-only, so rev4 ids — including 22 distinct statement-letter forms such
# as `ac-2_smt.j` — were written onto CdefControls as though they were rev5.
# Rev 5 renumbered control statements, so those ids address nothing in the rev5
# catalog: a control that looks mapped and resolves to no catalog entry.
#
# ── Deliberately reads the SHIPPED file, not the network ───────────────────
#
# AwsConfigRefreshService does this same reload, but fetches from GitHub first.
# A migration must not depend on egress: an air-gapped or proxy-restricted
# deployment would fail to boot its data migrations, and the vendored file is
# already in the image. The operator keeps the network path for a mid-release
# refresh; this is the deploy-time floor.
#
# ── Idempotent, and resumable from a partial run ───────────────────────────
#
# Both halves converge rather than accumulate. The converter reload deletes only
# the rows this pipeline authored (`category` = "mitre_vendored" / "aws_direct")
# and re-inserts them, so operator-added rows survive and a second run produces
# the same set. Re-enrichment is an upsert keyed by field name on each control,
# so a run that dies halfway leaves the documents it finished already correct and
# the rest untouched; running again completes them.
class ReenrichCdefNistMappingsFromRev5 < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  MAPPINGS_DIR = Rails.root.join("lib/data_mappings")

  def up
    defer_data_migration do
      reload_converter!(
        converter_type: "aws_config_to_nist",
        category:       "mitre_vendored",
        path:           MAPPINGS_DIR.join("mitre_aws_config_to_nist.json"),
        loader:         ->(doc) { AwsSecurityHub::AwsConfigMappingLoader.build(doc) }
      )

      reload_converter!(
        converter_type: "aws_security_hub_to_nist",
        category:       "aws_direct",
        path:           MAPPINGS_DIR.join("aws_security_hub_to_nist.json"),
        loader:         ->(doc) { AwsSecurityHub::AwsSecurityHubMappingLoader.build(doc) }
      )

      reenrich_documents!
    end
  end

  def down
    # Deliberately a no-op, not an oversight. Reversing would re-write rev4
    # statement-letter ids that address nothing in the rev5 catalog over the
    # correct rev5 ones — it would restore the defect. The prior values are not
    # worth keeping, and `source_control_id` still holds the Security Hub
    # identifier every mapping was derived from, so nothing is lost by going
    # forward only.
  end

  private

  def reload_converter!(converter_type:, category:, path:, loader:)
    converter = Converter.find_by(converter_type: converter_type)
    if converter.nil?
      say "#{converter_type}: not seeded on this instance, nothing to reload"
      return
    end

    unless path.exist?
      say "#{converter_type}: #{path.basename} missing from the image, skipping reload"
      return
    end

    rows = loader.call(JSON.parse(File.read(path)))
    if rows.empty?
      # Never blank a working converter because a file arrived unreadable.
      say "#{converter_type}: vendored file produced no rows, leaving existing entries alone"
      return
    end

    doc_rev = JSON.parse(File.read(path))["rev"]

    Converter.transaction do
      removed = converter.converter_entries.where(category: category).delete_all

      row_order_start = (converter.converter_entries.maximum(:row_order) || 0)
      entries = rows.map.with_index do |r, i|
        {
          converter_id: converter.id,
          source_id:    r["source_id"],
          target_id:    r["target_id"],
          relationship: r["relationship"],
          category:     r["category"],
          remarks:      r["remarks"],
          row_order:    row_order_start + i + 1,
          uuid:         SecureRandom.uuid,
          created_at:   Time.current,
          updated_at:   Time.current
        }
      end

      # on_conflict do nothing — an operator-added row using the same
      # (source_id, target_id) wins, exactly as in the refresh service.
      ConverterEntry.insert_all(entries, unique_by: :idx_converter_entries_unique_pair)

      # The converter must declare the revision its targets actually are, or the
      # next consumer inherits the same mismatch this migration exists to fix.
      converter.target_rev = doc_rev.to_s if doc_rev.present?
      converter.save!(validate: false) if converter.changed?

      say "#{converter_type}: replaced #{removed} #{category} rows with #{entries.length} " \
          "(#{rows.map { |r| r["source_id"] }.uniq.length} source ids, rev #{doc_rev})"
    end
  end

  # Re-run enrichment for every CDEF that holds AWS Security Hub controls.
  #
  # Scoped by `source_vocabulary` rather than by document source: a CDEF UPLOADED
  # through the UI is exactly the case #1103 reported, and it carries no
  # `import_metadata.source_type = "aws_labs"` to find it by.
  def reenrich_documents!
    service = CdefNistEnrichmentService.new
    document_ids = CdefControl
      .where(source_vocabulary: "aws_security_hub")
      .distinct
      .pluck(:cdef_document_id)
      .compact

    if document_ids.empty?
      say "No CDEF controls sourced from AWS Security Hub; nothing to re-enrich"
      return
    end

    enriched = 0
    failed   = 0
    CdefDocument.where(id: document_ids).find_each(batch_size: 25) do |document|
      enriched += service.enrich!(document)
      document.clear_nist_enrichment_failure!
    rescue StandardError => e
      # One unreadable document must not strand the rest — and it must not pass
      # for clean either (#968). The next run retries it.
      failed += 1
      document.record_nist_enrichment_failure!(e)
      say "  document #{document.id} (#{document.name}): #{e.class} — #{e.message}"
    end

    say "Re-enriched #{enriched} controls across #{document_ids.length} documents" \
        "#{failed.positive? ? ", #{failed} documents degraded" : ""}"
  end
end
