# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261018120000_add_registered_release_to_data_migration_runs.rb")

# #1223 — additive, idempotent, and safe on a database an older release
# migrated. DDL is transactional, so the drop rolls back with the example.
RSpec.describe AddRegisteredReleaseToDataMigrationRuns do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }
  after { DataMigrationRun.reset_column_information }

  def connection = ActiveRecord::Base.connection

  it "adds the column to a database that lacks it, and is a no-op the second time" do
    connection.remove_column(:data_migration_runs, :registered_release)
    DataMigrationRun.reset_column_information
    # The model has seen the table WITHOUT the column, as it has in a real
    # db:migrate process by the time this migration runs.
    expect(DataMigrationRun.column_names).not_to include("registered_release")

    migration.up
    expect { migration.up }.not_to raise_error

    expect(connection.column_exists?(:data_migration_runs, :registered_release, :string)).to be(true)
    expect(DataMigrationRun.column_names).to include("registered_release")
  end

  it "keeps existing rows, with the release unknown" do
    connection.remove_column(:data_migration_runs, :registered_release)
    DataMigrationRun.reset_column_information
    DataMigrationRun.create!(name: "RegisteredEarlier", status: "pending")

    migration.up

    expect(DataMigrationRun.find_by(name: "RegisteredEarlier").registered_release).to be_nil
  end

  # A database an older release migrated has no column; registration must not
  # break on it.
  it "lets a deferred migration register on a database without the column" do
    connection.remove_column(:data_migration_runs, :registered_release)
    DataMigrationRun.reset_column_information
    klass = Class.new(ActiveRecord::Migration[8.1]) { include DeferredDataMigration }
    stub_const("SpecDeferredWithoutColumn", klass)
    klass.class_eval { def up = defer_data_migration { :ok } }

    expect { SpecDeferredWithoutColumn.new.up }.to change(DataMigrationRun, :count).by(1)
  end
end
