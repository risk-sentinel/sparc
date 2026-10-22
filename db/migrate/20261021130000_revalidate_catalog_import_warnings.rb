# frozen_string_literal: true

# #1235 — catalog import no longer checks priority or baseline impact: a
# catalog defines controls, and both of those are what a profile sets. Every
# catalog imported before this still stores `missing_priority` and
# `missing_baseline` warnings (every NIST import warned about every control),
# and nothing in the catalog could ever clear them.
#
# Deferred (app/lib/deferred_data_migration.rb): it reads catalog content
# through CatalogImportValidationService and runs post-boot.
#
# ── What it does to existing data ──────────────────────────────────────────
#
# For each catalog whose stored warnings include either category, it re-runs
# the CURRENT validation and stores the result, exactly as the screen's
# Revalidate does. Only `import_warnings`, `import_warnings_summary` and
# `last_validated_at` change. Lifecycle status is untouched: a published
# catalog stays published, and so does whether its warnings were acknowledged.
#
# ── Idempotency ────────────────────────────────────────────────────────────
#
# Each catalog is updated on its own. A revalidated catalog no longer stores
# either category, so a re-run after a partial failure picks up only the
# catalogs it had not reached.
class RevalidateCatalogImportWarnings < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  RETIRED_CATEGORIES = %w[missing_priority missing_baseline].freeze

  def up
    defer_data_migration { revalidate_catalog_import_warnings }
  end

  def down
    # The retired warnings described nothing a catalog can correct.
  end

  def revalidate_catalog_import_warnings
    revalidated = 0
    ControlCatalog.find_each do |catalog|
      next unless retired_warnings?(catalog)

      result = CatalogImportValidationService.new(catalog).validate
      catalog.update_columns(
        metadata_extra: catalog.metadata_extra.merge(
          "import_warnings"         => result["import_warnings"] || [],
          "import_warnings_summary" => result["import_warnings_summary"] || {},
          "last_validated_at"       => Time.current.iso8601
        ),
        updated_at: Time.current
      )
      revalidated += 1
    end
    say "Revalidated #{revalidated} catalog(s) carrying retired priority/baseline warnings"
  end

  private

  def retired_warnings?(catalog)
    warnings = catalog.metadata_extra.is_a?(Hash) ? catalog.metadata_extra["import_warnings"] : nil
    Array(warnings).any? { |w| w.is_a?(Hash) && RETIRED_CATEGORIES.include?(w["category"]) }
  end
end
