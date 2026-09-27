# frozen_string_literal: true

# #1151 — repair a database that is behind db/schema.rb, additively.
#
#   bin/rails db:reconcile_schema             # apply, in one transaction
#   DRY_RUN=1 bin/rails db:reconcile_schema   # run the same statements, roll back
#
# Creates what is missing — extensions, tables, columns, indexes, foreign keys —
# and nothing else. It never drops, renames or retypes, and it refuses outright,
# changing nothing, when the drift is not additive or an addition is unsafe.
# See SchemaReconciliationService.
#
# The container entrypoint runs it after `db:prepare` and before
# `db:verify_schema`, so a squash that archived a migration a deployment never
# ran is repaired at boot instead of serving 500s.
namespace :db do
  desc "Create what db/schema.rb declares and the database lacks (additive only; DRY_RUN=1 to preview)"
  task reconcile_schema: :environment do
    result = SchemaReconciliationService.new(dry_run: ENV["DRY_RUN"].present?).call
    puts result.report

    abort("\ndb:reconcile_schema REFUSED — the database was not changed.") if result.refused?
  end
end
