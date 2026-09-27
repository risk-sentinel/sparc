# frozen_string_literal: true

# #1147 — the check a deploy should have been making all along.
#
#   bin/rails db:verify_schema             # structural drift fails
#   STRICT=1 bin/rails db:verify_schema    # definitional drift fails too
#
# Exits non-zero when the live database does not match `schema.rb`. Run it
# AFTER `db:migrate` in a deploy: "no pending migrations" only says the version
# table is current, which is precisely the claim that was true and useless when
# v1.16.2 shipped with seven columns missing.
#
# #1151 — the container entrypoint runs it before the web server binds, so a
# mismatched image and database fail the DEPLOY rather than serving 500s. It
# runs non-strict there (see SchemaDriftService for why); the upgrade-path CI
# job runs STRICT=1.
namespace :db do
  desc "Verify the live database matches db/schema.rb (exits 1 on drift; STRICT=1 includes definitional drift)"
  task verify_schema: :environment do
    strict = ENV["STRICT"].present?
    service = SchemaDriftService.new
    puts service.report(strict: strict)

    unless service.clean?(strict: strict)
      abort("\ndb:verify_schema FAILED — the database does not match db/schema.rb.\n" \
            "`bin/rails db:reconcile_schema` repairs what is additive (a missing table, column,\n" \
            "index, foreign key or extension). Anything it refuses needs a migration.\n" \
            "Do NOT run db:schema:load against a populated database: it would drop data.\n" \
            "For a database this release cannot reach yet: bin/schema_drift_sql | psql $DATABASE_URL")
    end
  end
end
