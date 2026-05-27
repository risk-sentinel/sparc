# frozen_string_literal: true

require "rails_helper"

# v1.8.3 — DeferredDataMigration mixin + runner.
#
# Specs use throwaway anonymous migration classes (assigned to
# top-level constants so safe_constantize can find them) so we can
# exercise the real code paths without depending on a specific
# real migration's body.
RSpec.describe DeferredDataMigrationRunner do
  # Reset thread-local + tracking rows between examples so state
  # from one test never leaks to the next.
  before do
    DeferredDataMigration.idle!
    DataMigrationRun.delete_all
  end

  # Helper: define an anonymous migration class bound to a top-level
  # constant so the runner can `safe_constantize` it by name.
  def define_migration(name, &block)
    klass = Class.new(ActiveRecord::Migration[8.1]) do
      include DeferredDataMigration
    end
    Object.const_set(name, klass)
    klass.class_exec(&block) if block
    klass
  end

  after do
    [ :SpecDeferredA, :SpecDeferredB, :SpecDeferredRaises, :SpecDeferredCounted ].each do |c|
      Object.send(:remove_const, c) if Object.const_defined?(c)
    end
  end

  describe "DeferredDataMigration mixin" do
    it "registers a pending DataMigrationRun when up runs in db:migrate context" do
      define_migration(:SpecDeferredA) do
        def up
          defer_data_migration { raise "should NOT execute in register mode" }
        end
      end

      expect {
        SpecDeferredA.new.up
      }.to change { DataMigrationRun.count }.by(1)

      run = DataMigrationRun.find_by(name: "SpecDeferredA")
      expect(run.status).to eq("pending")
      expect(run.version).to eq("1.0.0")
    end

    it "executes the block when DeferredDataMigration.executing is set (runner context)" do
      executed = false
      define_migration(:SpecDeferredA) do
        define_method(:up) do
          defer_data_migration { executed = true }
        end
      end

      DeferredDataMigration.executing!
      begin
        SpecDeferredA.new.up
      ensure
        DeferredDataMigration.idle!
      end

      expect(executed).to be(true)
    end

    it "honors a custom data_migration_version" do
      define_migration(:SpecDeferredA) do
        data_migration_version "2.5.1"
        def up
          defer_data_migration { :noop }
        end
      end

      SpecDeferredA.new.up
      expect(DataMigrationRun.find_by(name: "SpecDeferredA").version).to eq("2.5.1")
    end

    it "raises ArgumentError when defer_data_migration is called without a block" do
      define_migration(:SpecDeferredA) do
        def up
          defer_data_migration
        end
      end
      expect { SpecDeferredA.new.up }.to raise_error(ArgumentError, /block required/)
    end

    it "registration is idempotent — calling up twice doesn't duplicate the run row" do
      define_migration(:SpecDeferredA) do
        def up
          defer_data_migration { :noop }
        end
      end
      SpecDeferredA.new.up
      expect { SpecDeferredA.new.up }.not_to change { DataMigrationRun.count }
    end
  end

  describe ".run_all_pending" do
    it "runs each pending migration's block and marks completed" do
      counter = []
      define_migration(:SpecDeferredA) do
        define_method(:up) do
          defer_data_migration { counter << "A" }
        end
      end
      define_migration(:SpecDeferredB) do
        define_method(:up) do
          defer_data_migration { counter << "B" }
        end
      end

      # Register both as pending (db:migrate context)
      SpecDeferredA.new.up
      SpecDeferredB.new.up

      described_class.run_all_pending

      expect(counter).to match_array(%w[A B])
      expect(DataMigrationRun.find_by(name: "SpecDeferredA").status).to eq("completed")
      expect(DataMigrationRun.find_by(name: "SpecDeferredB").status).to eq("completed")
    end

    it "marks a migration failed when its block raises, and continues with the rest" do
      define_migration(:SpecDeferredRaises) do
        def up
          defer_data_migration { raise "boom" }
        end
      end
      define_migration(:SpecDeferredA) do
        def up
          defer_data_migration { :ok }
        end
      end

      SpecDeferredRaises.new.up
      SpecDeferredA.new.up

      described_class.run_all_pending

      raised = DataMigrationRun.find_by(name: "SpecDeferredRaises")
      expect(raised.status).to eq("failed")
      expect(raised.error_message).to match(/boom/)

      ok = DataMigrationRun.find_by(name: "SpecDeferredA")
      expect(ok.status).to eq("completed")
    end

    it "retries previously-failed migrations on subsequent runs" do
      attempts = 0
      define_migration(:SpecDeferredA) do
        define_method(:up) do
          defer_data_migration do
            attempts += 1
            raise "fail-once" if attempts == 1
          end
        end
      end

      SpecDeferredA.new.up
      described_class.run_all_pending
      expect(DataMigrationRun.find_by(name: "SpecDeferredA").status).to eq("failed")

      described_class.run_all_pending  # retry
      expect(DataMigrationRun.find_by(name: "SpecDeferredA").status).to eq("completed")
      expect(attempts).to eq(2)
    end

    it "marks failed when the class is no longer loadable (renamed / removed)" do
      DataMigrationRun.create!(name: "GoneClassName", status: "pending")
      described_class.run_all_pending

      gone = DataMigrationRun.find_by(name: "GoneClassName")
      expect(gone.status).to eq("failed")
      expect(gone.error_message).to match(/not loadable/)
    end

    it "resets stuck 'running' rows from a previous crashed container before processing" do
      # Simulate: row left running from a previous crashed container
      DataMigrationRun.create!(name: "GoneClassName", status: "running",
                                started_at: 1.hour.ago)

      described_class.run_all_pending

      run = DataMigrationRun.find_by(name: "GoneClassName")
      # Reset to pending → then runner tries to execute → class
      # missing → marked failed. End state: failed (and the previous-
      # crash error_message preserved? No — the runner overwrites it
      # with its own "not loadable" message on the new failure path.)
      expect(run.status).to eq("failed")
    end

    it "emits a data_migration_completed AuditEvent on success" do
      define_migration(:SpecDeferredA) do
        def up
          defer_data_migration { :ok }
        end
      end
      SpecDeferredA.new.up

      expect {
        described_class.run_all_pending
      }.to change { AuditEvent.where(action: "data_migration_completed").count }.by(1)

      event = AuditEvent.where(action: "data_migration_completed").last
      expect(event.metadata["name"]).to eq("SpecDeferredA")
    end

    it "emits a structured JSON log line per phase" do
      define_migration(:SpecDeferredA) do
        def up
          defer_data_migration { :ok }
        end
      end
      SpecDeferredA.new.up

      logs = []
      allow(Rails.logger).to receive(:info) { |msg| logs << msg }
      described_class.run_all_pending

      parsed = logs.filter_map { |l| begin; JSON.parse(l); rescue; nil; end }
                   .map { |h| h["deferred_data_migration"] }
                   .compact
      phases = parsed.map { |p| p["phase"] }
      expect(phases).to include("started", "completed")
      expect(parsed.find { |p| p["phase"] == "completed" }["name"]).to eq("SpecDeferredA")
    end
  end
end
