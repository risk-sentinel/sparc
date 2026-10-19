# frozen_string_literal: true

require "rails_helper"

# #1223 — the between-boots retry. It must cost nothing when nothing waits.
RSpec.describe DeferredDataMigrationSweepJob do
  it "does nothing when no row is awaiting this release" do
    DataMigrationRun.create!(name: "Raised", status: "failed", error_message: "RuntimeError: boom")
    expect(DeferredDataMigrationRunner).not_to receive(:run_all_pending)

    described_class.perform_now
  end

  it "runs the pending migrations when one is waiting" do
    DataMigrationRun.create!(name: "Waiting", status: "pending", registered_release: SparcConfig::VERSION)
    expect(DeferredDataMigrationRunner).to receive(:run_all_pending)

    described_class.perform_now
  end

  it "is scheduled in production every 5 minutes" do
    schedule = YAML.safe_load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true)

    expect(schedule.dig("production", "deferred_data_migration_sweep"))
      .to eq("class" => "DeferredDataMigrationSweepJob", "schedule" => "every 5 minutes")
  end
end
