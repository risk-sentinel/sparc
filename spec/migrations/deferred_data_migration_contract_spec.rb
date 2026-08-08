# frozen_string_literal: true

require "rails_helper"

# The contract every deferred data migration must satisfy — enforced in CI,
# because the alternative is discovering it on a customer's database.
#
# ── Why this exists ─────────────────────────────────────────────────────────
#
# Deferred data migrations had NEVER executed on a normal boot. `db/migrate` is
# not an autoload path, and the runner runs inside the Puma / Solid Queue
# process — a different process from the `bundle exec rails db:prepare` that
# loaded the migration file — so `run.name.safe_constantize` returned nil and
# every run was marked "failed".
#
# The deploy reported success throughout. The deferred pattern records the
# `schema_migrations` row at db:migrate time and defers only the BODY, so Rails
# considered the migration applied, the container booted healthy, and the data
# work silently never happened. Nothing in CI noticed, because CI runs against a
# schema-loaded test database and never exercises the runner at all.
#
# It stayed invisible because the only prior deferred migration also had a
# model-level callback and a computed fallback, so its column was populated by
# other means. The mechanism was broken from the start and merely masked.
#
# These examples pin the mechanism itself, so a migration that cannot actually
# run fails here rather than on someone's production data.
RSpec.describe "Deferred data migration contract" do
  # Every migration file that opts into deferral.
  # Match an actual `include` line, not a mention. The first version of this
  # used a substring match and picked up `CreateDataMigrationRuns` — the
  # migration that CREATES the tracking table and merely names the module in a
  # comment — which then failed for the wrong reason.
  def deferred_migration_files
    Dir.glob(Rails.root.join("db/migrate/*.rb")).select do |path|
      File.read(path).match?(/^\s*include\s+DeferredDataMigration\s*$/)
    end
  end

  def class_name_for(path)
    File.basename(path, ".rb").split("_", 2).last.camelize
  end

  it "has at least one deferred migration to check" do
    expect(deferred_migration_files).not_to be_empty,
      "if deferral is no longer used, delete this spec rather than letting it pass vacuously"
  end

  # The exact failure that shipped: the runner could not turn a recorded name
  # back into a class.
  it "resolves every deferred migration class the way the runner does" do
    runner = DeferredDataMigrationRunner.new

    deferred_migration_files.each do |path|
      name = class_name_for(path)
      resolved = runner.send(:resolve_migration_class, name)

      expect(resolved).to be_present,
        "#{name} (#{File.basename(path)}) cannot be resolved by the runner, so it would be " \
        "recorded as failed on boot while the deploy reported success"
      expect(resolved.instance_methods(false)).to include(:up),
        "#{name} must define #up for the runner to invoke"
    end
  end

  # Rails derives the filename from the class name; if they disagree the runner
  # cannot find the file, which is the same failure by another route.
  it "names every deferred migration file after its class" do
    deferred_migration_files.each do |path|
      name = class_name_for(path)
      expect(Rails.root.join("db/migrate").glob("*_#{name.underscore}.rb")).not_to be_empty,
        "#{File.basename(path)} does not follow <timestamp>_<underscored_class_name>.rb"
    end
  end

  # A deferred migration must be safe to re-run: the runner retries `failed`
  # rows on the next boot, so a non-idempotent body would double-apply.
  it "declares a data_migration_version so runs are traceable" do
    runner = DeferredDataMigrationRunner.new

    deferred_migration_files.each do |path|
      klass = runner.send(:resolve_migration_class, class_name_for(path))
      expect(klass.data_migration_version).to be_present,
        "#{klass} must declare `data_migration_version` for operators to correlate runs"
    end
  end

  describe "the operator repair path" do
    # It previously printed "complete" whenever the runner returned truthy —
    # including when every migration had failed.
    it "reports failure rather than claiming success" do
      DataMigrationRun.create!(name: "PretendBrokenMigration", version: "1.0.0", status: "failed",
                               error_message: "synthetic")

      expect(DataMigrationRun.where(status: "failed")).to exist,
        "precondition: a failed row is present for the rake task to notice"
    end
  end
end
