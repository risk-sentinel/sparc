# frozen_string_literal: true

# #1115 / #1172 — re-key an existing deployment's FedRAMP 20x KSI catalog onto
# what FedRAMP publishes, through the SAME importer an operator runs
# (FedrampKsiImportService; `bin/rails ksi:import`).
#
# Deferred (app/lib/deferred_data_migration.rb): it needs the retired-state
# columns from 20260928120000 and the Rev 5 catalog, and it runs post-boot.
#
# ── What it does to existing data ──────────────────────────────────────────
#
# Nothing is deleted. The owner-approved map (lib/data/fedramp/ksi_legacy_map.yml)
# renames ten indicators in place — their KsiValidations follow the row — and
# retires the other 44 with `superseded_by`, keeping their validations as
# history. AUTH is retired; five themes are renamed in place.
#
# ── Idempotency ────────────────────────────────────────────────────────────
#
# The importer is a no-op when the catalog already carries this snapshot's
# digest and its crosswalk, so a re-run after a partial failure converges; the
# import itself is one transaction, so there is no partial state to resume from.
#
# A REFUSED import raises, so the runner records the run as failed and retries
# it on the next boot, rather than the deploy reporting a re-key that did not
# happen.
class ImportFedrampKsiCatalogFromRules < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      result = FedrampKsiImportService.new.call
      raise FedrampKsiImportService::Refused, "FedRAMP KSI import refused: #{result.errors.join('; ')}" if result.refused?

      Rails.logger.info({ fedramp_ksi_import: { status: result.status, version: result.version, changes: result.changes } }.to_json)
    end
  end

  def down
    # Reversing would re-key assessments onto ids FedRAMP no longer publishes.
  end
end
