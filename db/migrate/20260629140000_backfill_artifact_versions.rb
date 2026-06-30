# frozen_string_literal: true

# #680 — seed one ArtifactVersion per existing evidence that has an attached
# file, so the version-history audit trail covers pre-existing artifacts from
# day one (not only those touched after deploy). Correctness doesn't depend on
# this — `Evidence#current_artifact_version` lazily mints on first access — but
# the backfill makes the history complete up front.
#
# Deferred (post-boot) so the container comes up immediately while the backfill
# runs in the background. See app/lib/deferred_data_migration.rb.
class BackfillArtifactVersions < ActiveRecord::Migration[8.1]
  include DeferredDataMigration

  def up
    defer_data_migration do
      Evidence.find_each do |evidence|
        next unless evidence.file.attached? && evidence.file_hash.present?
        next if evidence.artifact_versions.exists?

        evidence.mint_artifact_version!(reason: "backfill")
      end
    end
  end

  def down
    # No-op — artifact versions are audit history; not removed on rollback.
  end
end
