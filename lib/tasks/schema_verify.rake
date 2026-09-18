# frozen_string_literal: true

# #1147 — the check a deploy should have been making all along.
#
#   bin/rails db:verify_schema
#
# Exits non-zero when the live database is missing anything `schema.rb`
# declares. Run it AFTER `db:migrate` in a deploy: "no pending migrations" only
# says the version table is current, which is precisely the claim that was true
# and useless when v1.16.2 shipped with seven columns missing.
namespace :db do
  desc "Verify the live database matches db/schema.rb (exits 1 on drift)"
  task verify_schema: :environment do
    service = SchemaDriftService.new
    puts service.report

    unless service.clean?
      abort("\ndb:verify_schema FAILED — the database does not match db/schema.rb.\n" \
            "Apply the repair migration (RepairColumnsArchivedByTheSquash) or, for drift it\n" \
            "does not cover, generate a migration for the differences listed above.\n" \
            "Do NOT run db:schema:load against a populated database: it would drop data.")
    end
  end
end
