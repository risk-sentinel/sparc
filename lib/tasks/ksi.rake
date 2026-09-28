# #1115 / #1172 — build the FedRAMP 20x KSI catalog from the vendored
# FedRAMP/rules snapshot (lib/data/fedramp). Reads the vendored copy only —
# never the network. Operator-initiated; the same import is POST
# /api/v1/ksi_catalog/import.
#
# Usage:
#   bin/rails ksi:import           # import (a no-op when the snapshot is unchanged)
#   bin/rails 'ksi:import[true]'   # dry run: report the changes, then roll back
namespace :ksi do
  desc "Import the FedRAMP 20x KSI catalog from the vendored FedRAMP/rules snapshot (pass [true] for a dry run)"
  task :import, [ :dry_run ] => :environment do |_t, args|
    dry_run = ActiveModel::Type::Boolean.new.cast(args[:dry_run]) || false

    result = FedrampKsiImportService.new(dry_run: dry_run).call
    puts result.report
    exit 1 if result.refused?
  end
end
